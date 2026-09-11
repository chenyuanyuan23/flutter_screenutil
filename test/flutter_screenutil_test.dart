import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void main() {
  group('ScreenUtil', () {
    test('defaultSize', () {
      expect(ScreenUtil.defaultSize.width, 360);
      expect(ScreenUtil.defaultSize.height, 690);
    });
    test('单例', () {
      expect(ScreenUtil(), same(ScreenUtil()));
    });

    testWidgets('textScaleFactor 使用 TextScaler 数值且不会发生型别转换异常', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(750, 1334),
            textScaler: TextScaler.linear(1.25),
          ),
          child: _InitializeScreenUtilOnce(),
        ),
      );

      expect(ScreenUtil().textScaleFactor, 1.25);
    });

    testWidgets('一般手机横屏沿用旧版旋转前的直屏 scale', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.displayFeatures = const [];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);

      await tester.pumpWidget(const _InitializeScreenUtilWithoutMetricsSync());
      await tester.pump();

      expect(ScreenUtil().orientation, Orientation.portrait);
      expect(ScreenUtil().isFoldOpen, isFalse);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(390 / 750));
      expect(100.w, moreOrLessEquals(100 * 390 / 750));

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();

      expect(ScreenUtil().orientation, Orientation.landscape);
      expect(ScreenUtil().isFoldOpen, isFalse);
      expect(ScreenUtil().viewportWidth, 844);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(390 / 750));
      expect(ScreenUtil().scaleHeight, moreOrLessEquals(390 / 750));
      expect(100.w, moreOrLessEquals(100 * 390 / 750));

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      expect(ScreenUtil().orientation, Orientation.portrait);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(390 / 750));
      expect(ScreenUtil().scaleHeight, moreOrLessEquals(844 / 1334));
    });

    testWidgets('一般平板横屏仍依横屏设计宽计算', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.displayFeatures = const [];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);

      await tester.pumpWidget(const _InitializeScreenUtilWithoutMetricsSync());
      await tester.pump();

      expect(ScreenUtil().orientation, Orientation.landscape);
      expect(ScreenUtil().isFoldOpen, isFalse);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(1200 / 1334));
      expect(100.w, moreOrLessEquals(100 * 1200 / 1334));
    });

    testWidgets('使用实际视窗与 fold feature 记录收合及展开宽度', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.displayFeatures = const [];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);

      await tester.pumpWidget(const _InitializeScreenUtilOnce());
      await tester.pump();

      expect(ScreenUtil().screenWidth, 750);
      expect(ScreenUtil().viewportWidth, 750);
      expect(ScreenUtil().screenHeight, 1334);
      expect(ScreenUtil().foldedScreenWidth, 750);
      expect(ScreenUtil().unfoldedScreenWidth, 750);
      expect(ScreenUtil().flipScreenWidth, 750);
      expect(ScreenUtil().hasObservedFoldFeature, isFalse);
      expect(ScreenUtil().hasMeasuredBothFoldWidths, isFalse);
      expect(ScreenUtil().enableFoldWidthAdaptation, isTrue);

      // 收合／一般视窗使用当下实际宽度。
      tester.view.physicalSize = const Size(420, 900);
      await tester.pump();

      expect(ScreenUtil().screenWidth, 420);
      expect(ScreenUtil().viewportWidth, 420);
      expect(ScreenUtil().foldedScreenWidth, 420);
      expect(ScreenUtil().unfoldedScreenWidth, 420);
      expect(100.w, moreOrLessEquals(56));
      expect(100.h, moreOrLessEquals(100 * 900 / 1334));
      expect(100.sp, moreOrLessEquals(56));

      // 展开时 viewport 可能比 fold feature 先到。这个中间帧不得发布，
      // 否则 `.w/.sp` 会短暂用完整 900 宽度放大一倍。
      tester.view.physicalSize = const Size(900, 1200);
      await tester.pump();

      expect(ScreenUtil().screenWidth, 420);
      expect(ScreenUtil().viewportWidth, 420);
      expect(ScreenUtil().screenHeight, 900);
      expect(ScreenUtil().isFoldOpen, isFalse);

      // 系统出现 fold feature 才原子提交展开尺寸；不再靠宽高比猜测。
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(449, 0, 2, 1200),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ];
      await tester.pump();

      // 展开后 screenWidth 使用收合设计稿宽度计算 `.w`，代表单一 pane；
      // 真正的收合实宽仍由 foldedScreenWidth 保留。
      expect(ScreenUtil().screenWidth, 450);
      expect(ScreenUtil().viewportWidth, 900);
      expect(ScreenUtil().screenHeight, 1200);
      expect(ScreenUtil().foldedScreenWidth, 420);
      expect(ScreenUtil().unfoldedScreenWidth, 900);
      expect(ScreenUtil().flipScreenWidth, 900);
      expect(ScreenUtil().hasObservedFoldFeature, isTrue);
      expect(ScreenUtil().isFoldOpen, isTrue);
      expect(ScreenUtil().hasMeasuredBothFoldWidths, isTrue);
      expect(ScreenUtil().marginBorderWidth, 225);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(900 / 1500));
      expect(100.w, moreOrLessEquals(60));
      expect(100.h, moreOrLessEquals(100 * 1200 / 1334));
      expect(100.sp, moreOrLessEquals(60));

      // 无实体间隙的 fold 仍以系统回报的折线位置切出两个 450 pane。
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(450, 0, 0, 1200),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ];
      await tester.pump();

      expect(ScreenUtil().screenWidth, 450);
      expect(ScreenUtil().viewportWidth, 900);
      expect(ScreenUtil().unfoldedScreenWidth, 900);

      // 直向 viewport 的水平折线属于 Flip 类上下折装置，不得套用
      // 书本式折叠展开的 1500 宽设计稿。
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(0, 600, 900, 0),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await tester.pump();

      expect(ScreenUtil().isFoldOpen, isFalse);
      expect(ScreenUtil().screenWidth, 900);
      expect(ScreenUtil().viewportWidth, 900);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(900 / 750));
      expect(ScreenUtil().marginBorderWidth, 0);

      // 明确收到 Flip 类折线后，即使 feature 暂时消失也维持一般 viewport。
      tester.view.displayFeatures = const [];
      await tester.pump();

      expect(ScreenUtil().screenWidth, 900);
      expect(ScreenUtil().viewportWidth, 900);
      expect(ScreenUtil().isFoldOpen, isFalse);

      // 实际收合 viewport 到达后才一次提交新值，且不靠展开宽度除以二。
      tester.view.physicalSize = const Size(430, 920);
      await tester.pump();

      expect(ScreenUtil().screenWidth, 430);
      expect(ScreenUtil().viewportWidth, 430);
      expect(ScreenUtil().screenHeight, 920);
      expect(ScreenUtil().foldedScreenWidth, 430);
      expect(ScreenUtil().unfoldedScreenWidth, 900);
      expect(ScreenUtil().isFoldOpen, isFalse);
      expect(ScreenUtil().marginBorderWidth, 0);
    });

    testWidgets('vivo X Fold 展开比例与垂直折线会使用 1500 设计宽', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(638.67, 720);
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(318.33, 0, 2, 720),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);

      await tester.pumpWidget(const _InitializeScreenUtilWithoutMetricsSync());
      await tester.pump();

      expect(ScreenUtil().orientation, Orientation.portrait);
      expect(ScreenUtil().isFoldOpen, isTrue);
      expect(ScreenUtil().scaleWidth, moreOrLessEquals(638.67 / 1500));
      expect(100.w, moreOrLessEquals(100 * 638.67 / 1500));
    });
  });
}

class _InitializeScreenUtilOnce extends StatefulWidget {
  const _InitializeScreenUtilOnce();

  @override
  State<_InitializeScreenUtilOnce> createState() =>
      _InitializeScreenUtilOnceState();
}

class _InitializeScreenUtilOnceState extends State<_InitializeScreenUtilOnce> {
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
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _InitializeScreenUtilWithoutMetricsSync extends StatefulWidget {
  const _InitializeScreenUtilWithoutMetricsSync();

  @override
  State<_InitializeScreenUtilWithoutMetricsSync> createState() =>
      _InitializeScreenUtilWithoutMetricsSyncState();
}

class _InitializeScreenUtilWithoutMetricsSyncState
    extends State<_InitializeScreenUtilWithoutMetricsSync> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    ScreenUtil.init(
      context,
      designSize: const Size(750, 1334),
      unfoldedDesignSize: const Size(1500, 1334),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
