import 'package:firebase_auth/firebase_auth.dart';

final auth = FirebaseAuth.instance;

Future<UserCredential> signUp({
  required String email,
  required String password,
}) {
  return auth.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );
}

Future<UserCredential> signIn({
  required String email,
  required String password,
}) {
  return auth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );
}

Future<void> signOut() {
  return auth.signOut();
}