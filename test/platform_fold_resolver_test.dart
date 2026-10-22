import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ScreenUtil.resetPlatformFoldForTesting);

  void setView(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.displayFeatures = const [];
  }

  testWidgets('未安装判定器时，没有折线的近方形大屏仍按普通装置处理', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    expect(ScreenUtil.innerScalingEnabled, isFalse);
    expect(ScreenUtil().isFoldOpen, isFalse);
    expect(ScreenUtil().screenWidth, 669);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(669 / 750));
    expect(ScreenUtil().marginBorderWidth, 0);
  });

  testWidgets('判定器判为展开且启用内屏缩放：按展开设计稿缩放', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => true);
    expect(ScreenUtil.syncPlatformMetrics(const Size(669, 951)), isTrue);

    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().viewportWidth, 669);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(669 / 1500));
    expect(ScreenUtil().screenWidth, moreOrLessEquals(750 * 669 / 1500));
    expect(ScreenUtil().marginBorderWidth,
        moreOrLessEquals((669 - 750 * 669 / 1500) / 2));
    // 同一尺寸再次提交不算变化。
    expect(ScreenUtil.syncPlatformMetrics(const Size(669, 951)), isFalse);
  });

  testWidgets('判定器判为展开的横屏：设计稿随方向交换', (tester) async {
    setView(tester, const Size(951, 669));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => true);
    ScreenUtil.syncPlatformMetrics(const Size(951, 669));

    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(951 / 1500));
    expect(ScreenUtil().screenWidth, moreOrLessEquals(1334 * 951 / 1500));
  });

  testWidgets('判定器判为合上：按收合设计稿缩放', (tester) async {
    setView(tester, const Size(400, 900));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => false);
    ScreenUtil.syncPlatformMetrics(const Size(400, 900));

    expect(ScreenUtil().isFoldOpen, isFalse);
    expect(ScreenUtil().screenWidth, 400);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(400 / 750));
    expect(ScreenUtil().marginBorderWidth, 0);
  });

  testWidgets('展开但未启用内屏缩放：不切展开设计稿', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.setPlatformFoldResolver((_) => true);
    ScreenUtil.syncPlatformMetrics(const Size(669, 951));

    expect(ScreenUtil().isFoldOpen, isFalse);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(669 / 750));
  });

  testWidgets('判定器返回 null 时保持上次的值', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    bool? answer = true;
    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => answer);
    ScreenUtil.syncPlatformMetrics(const Size(669, 951));
    expect(ScreenUtil().isFoldOpen, isTrue);

    answer = null;
    expect(ScreenUtil.syncPlatformMetrics(const Size(400, 900)), isFalse);
    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().viewportWidth, 669);
  });

  testWidgets('视图尺寸变化经 didChangeMetrics 走判定器', (tester) async {
    setView(tester, const Size(400, 900));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((size) => size.width >= 600);
    ScreenUtil.syncPlatformMetrics(const Size(400, 900));
    expect(ScreenUtil().isFoldOpen, isFalse);

    tester.view.physicalSize = const Size(669, 951);
    await tester.pump();
    await tester.pump();

    expect(ScreenUtil().isFoldOpen, isTrue);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(669 / 1500));
  });

  testWidgets('resetPlatformFoldForTesting 清掉判定器与展开态', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => true);
    ScreenUtil.syncPlatformMetrics(const Size(669, 951));
    expect(ScreenUtil().isFoldOpen, isTrue);

    ScreenUtil.resetPlatformFoldForTesting();
    expect(ScreenUtil.innerScalingEnabled, isFalse);
    expect(ScreenUtil().isFoldOpen, isFalse);
    expect(ScreenUtil.syncPlatformMetrics(const Size(669, 951)), isFalse);
  });

  testWidgets('取消判定器后恢复按 displayFeatures 推断', (tester) async {
    setView(tester, const Size(669, 951));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pump();

    ScreenUtil.innerScalingEnabled = true;
    ScreenUtil.setPlatformFoldResolver((_) => true);
    ScreenUtil.syncPlatformMetrics(const Size(669, 951));
    expect(ScreenUtil().isFoldOpen, isTrue);

    ScreenUtil.setPlatformFoldResolver(null);
    expect(ScreenUtil.syncPlatformMetrics(const Size(669, 951)), isFalse);
    tester.view.physicalSize = const Size(670, 951);
    await tester.pump();
    await tester.pump();

    expect(ScreenUtil().isFoldOpen, isFalse);
    expect(ScreenUtil().scaleWidth, moreOrLessEquals(670 / 750));
  });
}

Widget _host() {
  return ScreenUtilInit(
    designSize: const Size(750, 1334),
    unfoldedDesignSize: const Size(1500, 1334),
    builder: (_, child) => const SizedBox.shrink(),
  );
}
