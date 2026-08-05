import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

/// Shows the package dialog with the text and icon defaults normally supplied
/// by a Cupertino page. Without this wrapper a Material app's navigator overlay
/// can expose Flutter's red/yellow debug fallback text style.
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

/// A Material switch on Android and a Liquid Glass switch on iOS.
class AdaptiveSettingsSwitch extends StatelessWidget {
  const AdaptiveSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.useOwnLayer = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Switch.adaptive(value: value, onChanged: onChanged);
    }

    final useClearEffect = context.select<FluxNewsState, bool>(
      (state) => state.iosClearLiquidGlass,
    );
    return SizedBox(
      height: 44,
      child: Center(
        child: Semantics(
          label: semanticLabel,
          enabled: onChanged != null,
          toggled: value,
          child: IgnorePointer(
            ignoring: onChanged == null,
            child: Opacity(
              opacity: onChanged == null ? 0.45 : 1,
              child: GlassSwitch(
                value: value,
                onChanged: onChanged ?? (_) {},
                semanticLabel: semanticLabel,
                useOwnLayer: useOwnLayer,
                quality: GlassQuality.standard,
                settings: iosLiquidGlassSettings(
                  context,
                  useClearEffect: useClearEffect,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Material dropdown on Android and an anchored Liquid Glass menu on iOS.
class AdaptiveSettingsDropdown<T> extends StatelessWidget {
  const AdaptiveSettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.elevation = 8,
    this.underline,
    this.alignment = AlignmentDirectional.centerStart,
    this.isExpanded = false,
    this.menuMaxHeight,
    this.selectedItemBuilder,
    this.hint,
    this.disabledHint,
    this.icon,
  });

  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final int elevation;
  final Widget? underline;
  final AlignmentGeometry alignment;
  final bool isExpanded;
  final double? menuMaxHeight;
  final DropdownButtonBuilder? selectedItemBuilder;
  final Widget? hint;
  final Widget? disabledHint;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        elevation: elevation,
        underline: underline,
        alignment: alignment,
        isExpanded: isExpanded,
        menuMaxHeight: menuMaxHeight,
        selectedItemBuilder: selectedItemBuilder,
        hint: hint,
        disabledHint: disabledHint,
        icon: icon,
      );
    }

    final options = items ?? <DropdownMenuItem<T>>[];
    final selectedIndex = options.indexWhere((item) => item.value == value);
    final selectedWidgets = selectedItemBuilder?.call(context);
    final selectedChild = selectedIndex >= 0
        ? selectedWidgets != null && selectedIndex < selectedWidgets.length
            ? selectedWidgets[selectedIndex]
            : options[selectedIndex].child
        : onChanged == null
            ? disabledHint ?? hint ?? const SizedBox.shrink()
            : hint ?? const SizedBox.shrink();
    final useClearEffect = context.select<FluxNewsState, bool>(
      (state) => state.iosClearLiquidGlass,
    );
    final foreground = iosLiquidGlassForeground(context);
    final enabled = onChanged != null && options.isNotEmpty;
    final optionLabels = options.map(_optionLabel).toList(growable: false);
    var longestLabelLength = 0;
    for (final label in optionLabels) {
      if (label.length > longestLabelLength) {
        longestLabelLength = label.length;
      }
    }
    final maximumMenuWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(180.0, 300.0);
    final menuWidth =
        (80.0 + longestLabelLength * 8.2).clamp(180.0, maximumMenuWidth);
    final menuItemHeights = optionLabels
        .map((label) => label.length > 28 ? 56.0 : 44.0)
        .toList(growable: false);
    final naturalMenuHeight = menuItemHeights.fold<double>(
          24,
          (height, itemHeight) => height + itemHeight,
        ) +
        (options.isEmpty ? 0 : (options.length - 1) * 2);
    final mediaQuery = MediaQuery.of(context);
    final maximumMenuHeight =
        mediaQuery.size.height - mediaQuery.padding.vertical - 44;
    final resolvedMenuHeight =
        menuMaxHeight ?? naturalMenuHeight.clamp(68.0, maximumMenuHeight);
    T? pendingSelection;
    var hasPendingSelection = false;

    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GlassMenu(
          autoAdjustToScreen: true,
          menuPadding: const EdgeInsets.all(12),
          menuWidth: menuWidth,
          // A non-null height selects GlassMenu's regular GestureDetector tap
          // path. Its natural-height slide-to-select path can miss rows after
          // auto-positioning the overlay near a screen edge.
          menuHeight: resolvedMenuHeight,
          menuBorderRadius: 24,
          itemBorderRadius: 16,
          quality: GlassQuality.standard,
          settings: iosLiquidGlassMenuSettings(
            context,
            useClearEffect: useClearEffect,
          ),
          onClose: () {
            if (!hasPendingSelection) return;
            final selection = pendingSelection;
            hasPendingSelection = false;
            pendingSelection = null;
            onChanged?.call(selection);
          },
          triggerBuilder: (context, toggleMenu) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? toggleMenu : null,
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.standard,
              settings: iosLiquidGlassSettings(
                context,
                useClearEffect: useClearEffect,
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 10, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: isExpanded ? 0 : 76,
                  minHeight: 28,
                  maxWidth: isExpanded ? double.infinity : 230,
                ),
                child: Row(
                  mainAxisSize:
                      isExpanded ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Flexible(
                      child: DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground),
                        child: selectedChild,
                      ),
                    ),
                    const SizedBox(width: 8),
                    icon ??
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 14,
                          color: foreground,
                        ),
                  ],
                ),
              ),
            ),
          ),
          items: options.asMap().entries.map((entry) {
            final option = entry.value;
            final label = optionLabels[entry.key];
            final isSelected = option.value == value;
            return GlassMenuItem(
              title: label,
              enabled: option.enabled,
              height: menuItemHeights[entry.key],
              maxLines: 2,
              titleStyle: TextStyle(
                inherit: false,
                color: foreground,
                fontSize: 17,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
              trailing: isSelected
                  ? Icon(
                      CupertinoIcons.check_mark,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    )
                  : null,
              onTap: () {
                if (option.value != value) {
                  pendingSelection = option.value;
                  hasPendingSelection = true;
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _optionLabel(DropdownMenuItem<T> option) {
    final optionValue = option.value;
    if (optionValue is KeyValueRecordType) return optionValue.value;
    if (option.child is Text) {
      final text = option.child as Text;
      return text.data ?? text.textSpan?.toPlainText() ?? '$optionValue';
    }
    return '$optionValue';
  }
}

/// A regular Material field on Android and a standalone glass field on iOS.
class AdaptiveSettingsTextField extends StatelessWidget {
  const AdaptiveSettingsTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.style,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.enabled,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.useOwnLayer = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool? enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        style: style,
        decoration: decoration,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        maxLines: maxLines,
        minLines: minLines,
        enabled: enabled,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );
    }

    final useClearEffect = context.select<FluxNewsState, bool>(
      (state) => state.iosClearLiquidGlass,
    );
    return GlassTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: decoration.hintText ?? decoration.labelText,
      prefixIcon: decoration.prefixIcon,
      suffixIcon: decoration.suffixIcon,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLines: maxLines ?? 1,
      minLines: minLines,
      enabled: enabled ?? true,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textStyle: style,
      useOwnLayer: useOwnLayer,
      quality: GlassQuality.standard,
      settings: iosLiquidGlassSettings(
        context,
        useClearEffect: useClearEffect,
      ),
    );
  }
}

/// A text action that preserves Material behavior on Android.
class AdaptiveSettingsButton extends StatelessWidget {
  const AdaptiveSettingsButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDestructive = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return OutlinedButton(onPressed: onPressed, child: child);
    }
    final useClearEffect = context.select<FluxNewsState, bool>(
      (state) => state.iosClearLiquidGlass,
    );
    final foreground = isDestructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.activeBlue.resolveFrom(context);
    return GlassButton.custom(
      onTap: onPressed ?? () {},
      enabled: onPressed != null,
      height: 44,
      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
      glowColor: isDestructive
          ? CupertinoColors.systemRed.withValues(alpha: 0.22)
          : null,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: iosLiquidGlassSettings(
        context,
        useClearEffect: useClearEffect,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A compact app-bar action with Liquid Glass rendering on iOS.
class AdaptiveSettingsIconButton extends StatelessWidget {
  const AdaptiveSettingsIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.loading = false,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      if (loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      return IconButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
    }

    final useClearEffect = context.select<FluxNewsState, bool>(
      (state) => state.iosClearLiquidGlass,
    );
    final foreground = iosLiquidGlassForeground(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: loading
          ? GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.standard,
              settings: iosLiquidGlassSettings(
                context,
                useClearEffect: useClearEffect,
              ),
              width: 44,
              height: 44,
              child: CupertinoActivityIndicator(color: foreground),
            )
          : GlassIconButton(
              icon: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: icon,
              ),
              onPressed: onPressed,
              semanticLabel: tooltip,
              useOwnLayer: true,
              quality: GlassQuality.standard,
              settings: iosLiquidGlassSettings(
                context,
                useClearEffect: useClearEffect,
              ),
            ),
    );
  }
}
