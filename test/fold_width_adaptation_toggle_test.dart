import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _openFold = DisplayFeature(
  bounds: Rect.fromLTWH(449, 0, 2, 1200),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

void main() {
  testWidgets('ScreenUtilInit 可停用并重新启用折叠宽度修正', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.displayFeatures = const [_openFold];
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDisplayFeatures);

    await tester.pumpWidget(_host(enableFoldWidthAdaptation: false));
    await tester.pump();

    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().enableFoldWidthAdaptation, isFalse);
    expect(ScreenUtil().screenWidth, 900);
    expect(ScreenUtil().viewportWidth, 900);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(900 / 750));
    expect(100.w, moreOrLessEquals(120));
    expect(ScreenUtil().marginBorderWidth, 0);

    await tester.pumpWidget(_host(enableFoldWidthAdaptation: true));
    await tester.pump();

    expect(ScreenUtil().enableFoldWidthAdaptation, isTrue);
    expect(ScreenUtil().screenWidth, 450);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(900 / 1500));
    expect(100.w, moreOrLessEquals(60));
    expect(ScreenUtil().marginBorderWidth, 225);
  });
}

Widget _host({required bool enableFoldWidthAdaptation}) {
  return ScreenUtilInit(
    designSize: const Size(750, 1334),
    unfoldedDesignSize: const Size(1500, 1334),
    enableFoldWidthAdaptation: enableFoldWidthAdaptation,
    builder: (_, child) => const SizedBox.shrink(),
  );
}
