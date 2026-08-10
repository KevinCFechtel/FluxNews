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

  testWidgets('iPhone edge facade configures native-like top and bottom fades',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
        child: IOSNewsScrollEdgeEffect(
          topChromeExtent: 68,
          isTablet: false,
          child: SizedBox.expand(),
        ),
      ),
    ));

    final effect = tester
        .widget<GlassScrollEdgeEffect>(find.byType(GlassScrollEdgeEffect));
    expect(effect.topFadeHeight, 93);
    expect(effect.bottomFadeHeight, 59);
    expect(effect.fadeBottom, isTrue);
    expect(effect.style, GlassScrollEdgeStyle.soft);
  });

  testWidgets('iPad edge facade omits the unused bottom fade', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: IOSNewsScrollEdgeEffect(
        topChromeExtent: 68,
        isTablet: true,
        child: SizedBox.expand(),
      ),
    ));

    final effect = tester
        .widget<GlassScrollEdgeEffect>(find.byType(GlassScrollEdgeEffect));
    expect(effect.fadeTop, isTrue);
    expect(effect.fadeBottom, isFalse);
  });
}
