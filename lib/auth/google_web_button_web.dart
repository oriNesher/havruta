import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

Widget googleWebButton({required double width}) => SizedBox(
  height: 44,
  child: gsi.renderButton(
    configuration: gsi.GSIButtonConfiguration(
      type: gsi.GSIButtonType.standard,
      theme: gsi.GSIButtonTheme.filledBlack,
      size: gsi.GSIButtonSize.large,
      text: gsi.GSIButtonText.continueWith,
      shape: gsi.GSIButtonShape.pill,
      // Google caps the rendered button at 400px wide.
      minimumWidth: width.clamp(200, 400).toDouble(),
    ),
  ),
);
