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
  testWidgets('直接展开使用预取收合实宽，收合后以 viewport 更新', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.displayFeatures = const [];
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDisplayFeatures);

    await tester.pumpWidget(const _MetricsHost());
    await tester.pump();

    expect(ScreenUtil().screenWidth, 450);
    expect(ScreenUtil().foldedScreenWidth, 430);
    expect(ScreenUtil().unfoldedScreenWidth, 900);
    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().hasObservedFoldFeature, isFalse);
    expect(ScreenUtil().hasMeasuredBothFoldWidths, isTrue);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(900 / 1500));
    expect(100.w, moreOrLessEquals(60));
    expect(100.h, moreOrLessEquals(100 * 1200 / 1334));
    expect(100.sp, moreOrLessEquals(60));

    // 原生预取让首帧无需等待 feature；feature 到达后保持相同结果。
    tester.view.displayFeatures = const [_openFold];
    await tester.pump();
    expect(ScreenUtil().screenWidth, 450);
    expect(ScreenUtil().hasObservedFoldFeature, isTrue);
    expect(100.w, moreOrLessEquals(60));

    // feature 先消失但 viewport 还很宽时，不得把 900 认成收合宽度。
    tester.view.displayFeatures = const [];
    await tester.pump();
    expect(ScreenUtil().screenWidth, 450);
    expect(ScreenUtil().isFoldOpen, isTrue);

    tester.view.physicalSize = const Size(430, 920);
    await tester.pump();
    expect(ScreenUtil().screenWidth, 430);
    expect(ScreenUtil().foldedScreenWidth, 430);
    expect(ScreenUtil().hasMeasuredBothFoldWidths, isTrue);
    expect(ScreenUtil().marginBorderWidth, 0);
    expect(100.w, moreOrLessEquals(430 / 7.5));
    expect(100.h, moreOrLessEquals(100 * 920 / 1334));
    expect(100.sp, moreOrLessEquals(430 / 7.5));

    final metricsProbe = _ScaleOnMetricsProbe();
    WidgetsBinding.instance.addObserver(metricsProbe);
    addTearDown(() => WidgetsBinding.instance.removeObserver(metricsProbe));

    // 收合 -> 展开时 viewport 会比 fold feature 先变宽；第一帧就必须切换
    // 展开设计稿，避免外层已移动但内部 `.w/.sp` 仍按收合比例放大。
    tester.view.physicalSize = const Size(460, 940);
    await tester.pump();
    expect(ScreenUtil().screenWidth, moreOrLessEquals(230));
    expect(ScreenUtil().viewportWidth, 460);
    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(100.w, moreOrLessEquals(100 * 460 / 1500));
    expect(100.sp, moreOrLessEquals(100 * 460 / 1500));
    expect(metricsProbe.lastScaleWidth, moreOrLessEquals(460 / 1500));

    // 后续 viewport 持续增长但 feature 尚未到达，也继续使用展开设计稿。
    tester.view.physicalSize = const Size(700, 1100);
    await tester.pump();
    expect(ScreenUtil().screenWidth, moreOrLessEquals(350));
    expect(ScreenUtil().viewportWidth, 700);
    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(100.w, moreOrLessEquals(100 * 700 / 1500));

    // feature 到达后 screenWidth 仍由收合设计稿宽经 `.w` 换算，结果保持连续。
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.displayFeatures = const [_openFold];
    await tester.pump();
    expect(ScreenUtil().screenWidth, 450);
    expect(ScreenUtil().foldedScreenWidth, 430);
    expect(100.w, moreOrLessEquals(60));
    expect(100.h, moreOrLessEquals(100 * 1200 / 1334));
    expect(100.sp, moreOrLessEquals(60));

    // 收合后若实际 viewport 变为 440，缩放与实测宽度都同步更新。
    tester.view.displayFeatures = const [];
    tester.view.physicalSize = const Size(440, 930);
    await tester.pump();
    expect(ScreenUtil().screenWidth, 440);
    expect(ScreenUtil().foldedScreenWidth, 440);
    expect(100.w, moreOrLessEquals(440 / 7.5));
  });
}

class _ScaleOnMetricsProbe with WidgetsBindingObserver {
  double? lastScaleWidth;

  @override
  void didChangeMetrics() {
    lastScaleWidth = ScreenUtil().scaleWidth;
  }
}

class _MetricsHost extends StatefulWidget {
  const _MetricsHost();

  @override
  State<_MetricsHost> createState() => _MetricsHostState();
}

class _MetricsHostState extends State<_MetricsHost> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      ScreenUtil.updateMetrics(context);
    } else {
      _initialized = true;
      ScreenUtil.init(
        context,
        designSize: const Size(750, 1334),
        unfoldedDesignSize: const Size(1500, 1334),
        foldedScreenWidth: 430,
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
