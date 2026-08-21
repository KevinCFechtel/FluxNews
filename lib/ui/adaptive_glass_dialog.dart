import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Shows a readable Liquid Glass dialog inside the app's Material navigator.
///
/// Callers keep the Android Material dialog as their explicit fallback. This
/// helper supplies the Cupertino text and icon defaults that are otherwise
/// missing from the navigator overlay.
Future<T?> showAdaptiveGlassDialog<T>({
  required BuildContext context,
  required List<GlassDialogAction> actions,
  String? title,
  String? message,
  Widget? content,
  LiquidGlassSettings? settings,
  GlassQuality quality = GlassQuality.standard,
  bool barrierDismissible = false,
  Color? barrierColor,
  double maxWidth = 280,
}) {
  return showCupertinoDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    builder: (dialogContext) {
      final foreground = CupertinoColors.label.resolveFrom(dialogContext);
      final textStyle =
          CupertinoTheme.of(dialogContext).textTheme.textStyle.copyWith(
                color: foreground,
                fontSize: 17,
                decoration: TextDecoration.none,
                decorationColor: const Color(0x00000000),
              );
      return DefaultTextStyle(
        style: textStyle,
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 22),
          child: GlassDialog(
            title: title,
            message: message,
            content: content,
            actions: actions,
            settings: settings,
            quality: quality,
            maxWidth: maxWidth,
          ),
        ),
      );
    },
  );
}

/// Compatibility alias for existing Settings call sites.
Future<T?> showAdaptiveSettingsGlassDialog<T>({
  required BuildContext context,
  required List<GlassDialogAction> actions,
  String? title,
  String? message,
  Widget? content,
  LiquidGlassSettings? settings,
  GlassQuality quality = GlassQuality.standard,
  bool barrierDismissible = false,
  Color? barrierColor,
  double maxWidth = 280,
}) {
  return showAdaptiveGlassDialog<T>(
    context: context,
    actions: actions,
    title: title,
    message: message,
    content: content,
    settings: settings,
    quality: quality,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    maxWidth: maxWidth,
  );
}
