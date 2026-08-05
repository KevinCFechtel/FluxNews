import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('clear light preset is less frosted than high contrast',
      (tester) async {
    late BuildContext testContext;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: Builder(builder: (context) {
        testContext = context;
        return const SizedBox.shrink();
      }),
    ));

    final highContrast = iosLiquidGlassSettings(
      testContext,
      useClearEffect: false,
    );
    final clear = iosLiquidGlassSettings(
      testContext,
      useClearEffect: true,
    );

    expect(highContrast.blur, 16);
    expect(clear.blur, 4);
    expect(clear.backerColor!.a, lessThan(highContrast.backerColor!.a));
    expect(clear.thickness, greaterThan(highContrast.thickness));
    final menu = iosLiquidGlassMenuSettings(
      testContext,
      useClearEffect: true,
    );
    expect(menu.blur, greaterThan(clear.blur));
    expect(menu.glassColor.a, greaterThan(clear.glassColor.a));
    expect(
      iosLiquidGlassQuality(useClearEffect: true),
      GlassQuality.premium,
    );
  });

  testWidgets('clear dark preset is less frosted than high contrast',
      (tester) async {
    late BuildContext testContext;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(builder: (context) {
        testContext = context;
        return const SizedBox.shrink();
      }),
    ));

    final highContrast = iosLiquidGlassSettings(
      testContext,
      useClearEffect: false,
    );
    final clear = iosLiquidGlassSettings(
      testContext,
      useClearEffect: true,
    );

    expect(highContrast.blur, 16);
    expect(clear.blur, 4);
    expect(clear.backerColor!.a, lessThan(highContrast.backerColor!.a));
    expect(clear.saturation, greaterThan(highContrast.saturation));
    final menu = iosLiquidGlassMenuSettings(
      testContext,
      useClearEffect: true,
    );
    expect(menu.blur, greaterThan(clear.blur));
    expect(menu.glassColor.a, greaterThan(clear.glassColor.a));
    expect(
      iosLiquidGlassQuality(useClearEffect: false),
      GlassQuality.standard,
    );
  });
}
