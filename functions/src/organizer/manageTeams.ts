import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {OrganizerError} from "./errors";
import {cleanTeamName, MAX_TEAMS, requireTeamOp} from "./teams";

interface ManageTeamsRequest {
  competitionId: string;
  op: "create" | "rename" | "delete" | "assign";
  teamId?: string | null;
  name?: string;
  /** assign: the participant (teamId null takes them off any team). */
  uid?: string;
}

/**
 * Organizer team management: create, rename and delete teams
 * (competitions/{id}/teams/{teamId}), and put a participant on one
 * (participants/{uid}.teamId, server-owned). Teams don't change who wins:
 * they're a team leaderboard (ranked by average progress per member) and
 * an audience — in a large challenge, teammates see each other's activity.
 * Deleting a team takes everyone off it. Every change is audited.
 */
export const manageTeams = onCall<ManageTeamsRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const op = requireTeamOp(request.data?.op);
    const db = admin.firestore();

    const result = await db.runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const teamsRef = ctx.ref.collection("teams");
      const teamsSnap = await tx.get(teamsRef);
      const teams = new Map(teamsSnap.docs.map((doc) =>
        [doc.id, (doc.data().name as string | undefined) ?? ""]));
      const rawTeamId = request.data?.teamId;
      const teamId = typeof rawTeamId === "string" && rawTeamId ?
        rawTeamId : null;
      const requireTeam = () => {
        if (!teamId || !teams.has(teamId)) {
          throw new OrganizerError("That team doesn't exist.");
        }
        return teamId;
      };

      if (op === "create") {
        if (teams.size >= MAX_TEAMS) {
          throw new OrganizerError(
            `A challenge can have at most ${MAX_TEAMS} teams.`);
        }
        const name = cleanTeamName(request.data?.name, [...teams.values()]);
        const ref = teamsRef.doc();
        tx.set(ref, {
          name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writeAudit(tx, ctx, {action: "createTeam", after: {team: name}});
        return {teamId: ref.id};
      }

      if (op === "rename") {
        const id = requireTeam();
        const name = cleanTeamName(request.data?.name,
          [...teams.entries()].filter(([k]) => k !== id).map(([, v]) => v));
        tx.update(teamsRef.doc(id), {name});
        writeAudit(tx, ctx, {
          action: "renameTeam",
          before: {team: teams.get(id)},
          after: {team: name},
        });
        return {teamId: id};
      }

      if (op === "delete") {
        const id = requireTeam();
        const members = await tx.get(ctx.ref.collection("participants")
          .where("teamId", "==", id));
        for (const member of members.docs) {
          tx.update(member.ref, {teamId: admin.firestore.FieldValue.delete()});
        }
        tx.delete(teamsRef.doc(id));
        writeAudit(tx, ctx, {
          action: "deleteTeam",
          before: {team: teams.get(id), members: members.size},
        });
        return {teamId: id};
      }

      // assign
      const targetUid = request.data?.uid;
      if (typeof targetUid !== "string" || !targetUid) {
        throw new OrganizerError("Pick someone to put on a team.");
      }
      if (teamId !== null) requireTeam();
      const participantRef = ctx.ref.collection("participants").doc(targetUid);
      const participantSnap = await tx.get(participantRef);
      if (!participantSnap.exists) {
        throw new OrganizerError("They aren't in this challenge.");
      }
      const before = participantSnap.data()?.teamId ?? null;
      tx.update(participantRef, {
        teamId: teamId ?? admin.firestore.FieldValue.delete(),
      });
      writeAudit(tx, ctx, {
        action: "assignTeam",
        targetUid,
        targetUsername: participantSnap.data()?.username ?? null,
        before: {team: before ? teams.get(before) ?? null : null},
        after: {team: teamId ? teams.get(teamId) ?? null : null},
      });
      return {teamId};
    });

    logger.info("Teams changed", {competitionId, uid, op, result});
    return result;
  })
);
