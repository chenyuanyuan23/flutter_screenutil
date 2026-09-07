import 'package:flutter/widgets.dart';

import 'screen_util.dart';

typedef RebuildFactor = bool Function(MediaQueryData old, MediaQueryData data);

typedef ScreenUtilInitBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

class RebuildFactors {
  const RebuildFactors._();

  static bool size(MediaQueryData old, MediaQueryData data) {
    return old.size != data.size;
  }

  static bool orientation(MediaQueryData old, MediaQueryData data) {
    return old.orientation != data.orientation;
  }

  static bool sizeAndViewInsets(MediaQueryData old, MediaQueryData data) {
    return old.viewInsets != data.viewInsets;
  }

  static bool all(MediaQueryData old, MediaQueryData data) {
    return old != data;
  }
}

class ScreenUtilInit extends StatefulWidget {
  /// A helper widget that initializes [ScreenUtil]
  const ScreenUtilInit({
    Key? key,
    required this.builder,
    this.child,
    this.rebuildFactor = RebuildFactors.size,
    this.designSize = ScreenUtil.defaultSize,
    this.unfoldedDesignSize,
    this.foldedScreenWidth,
    this.splitScreenMode = false,
    this.minTextAdapt = false,
    this.useInheritedMediaQuery = false,
    this.scaleByHeight = false,
    this.enableFoldWidthAdaptation = true,
  }) : super(key: key);

  final ScreenUtilInitBuilder builder;
  final Widget? child;
  final bool splitScreenMode;
  final bool minTextAdapt;
  final bool useInheritedMediaQuery;
  final bool scaleByHeight;

  /// Whether unfolded foldables apply the narrow width correction to `.w/.sp`.
  /// Defaults to true. Fold metrics remain available when disabled.
  final bool enableFoldWidthAdaptation;
  final RebuildFactor rebuildFactor;

  /// The [Size] of the device in the design draft, in dp
  final Size designSize;

  /// 折叠展开状态使用的设计稿尺寸；未传时与 [designSize] 相同。
  final Size? unfoldedDesignSize;

  /// 原生层预取的收合屏幕实际逻辑宽度。
  final double? foldedScreenWidth;

  @override
  State<ScreenUtilInit> createState() => _ScreenUtilInitState();
}

class _ScreenUtilInitState extends State<ScreenUtilInit>
    with WidgetsBindingObserver {
  MediaQueryData? _mediaQueryData;

  bool wrappedInMediaQuery = false;

  WidgetsBinding get binding => WidgetsFlutterBinding.ensureInitialized();

  MediaQueryData get mediaQueryData => _mediaQueryData!;

  MediaQueryData get newData {
    final data = MediaQuery.maybeOf(context);

    if (data != null) {
      if (widget.useInheritedMediaQuery) {
        wrappedInMediaQuery = true;
      }
      return data;
    }

    return MediaQueryData.fromView(View.of(context));
  }

  _updateTree(Element el) {
    el.markNeedsBuild();
    el.visitChildren(_updateTree);
  }

  @override
  void initState() {
    super.initState();
    binding.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    final data = newData;
    final old = _mediaQueryData;
    if (old == null) {
      _mediaQueryData = data;
      return;
    }

    if (widget.scaleByHeight || widget.rebuildFactor(old, data)) {
      _mediaQueryData = data;
      _updateTree(context as Element);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mediaQueryData == null) _mediaQueryData = newData;
    didChangeMetrics();
  }

  @override
  void dispose() {
    binding.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext _context) {
    if (mediaQueryData.size == Size.zero) return const SizedBox.shrink();
    if (!wrappedInMediaQuery) {
      return MediaQuery(
        data: mediaQueryData,
        child: Builder(
          builder: (__context) {
            ScreenUtil.init(
              __context,
              designSize: widget.designSize,
              unfoldedDesignSize: widget.unfoldedDesignSize,
              foldedScreenWidth: widget.foldedScreenWidth,
              splitScreenMode: widget.splitScreenMode,
              minTextAdapt: widget.minTextAdapt,
              scaleByHeight: widget.scaleByHeight,
              enableFoldWidthAdaptation: widget.enableFoldWidthAdaptation,
            );
            final deviceData = MediaQuery.maybeOf(__context);
            final deviceSize = deviceData?.size ?? widget.designSize;
            return MediaQuery(
              data: MediaQueryData.fromView(View.of(__context)),
              child: Container(
                width: deviceSize.width,
                height: deviceSize.height,
                child: FittedBox(
                  fit: BoxFit.none,
                  alignment: Alignment.center,
                  child: Container(
                    width: widget.scaleByHeight
                        ? (deviceSize.height * widget.designSize.width) /
                            widget.designSize.height
                        : deviceSize.width,
                    height: deviceSize.height,
                    child: widget.builder(__context, widget.child),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    ScreenUtil.init(
      _context,
      designSize: widget.designSize,
      unfoldedDesignSize: widget.unfoldedDesignSize,
      foldedScreenWidth: widget.foldedScreenWidth,
      splitScreenMode: widget.splitScreenMode,
      minTextAdapt: widget.minTextAdapt,
      scaleByHeight: widget.scaleByHeight,
      enableFoldWidthAdaptation: widget.enableFoldWidthAdaptation,
    );
    final deviceData = MediaQuery.maybeOf(_context);
    final deviceSize = deviceData?.size ?? widget.designSize;
    return Container(
      width: deviceSize.width,
      height: deviceSize.height,
      child: FittedBox(
        fit: BoxFit.none,
        alignment: Alignment.center,
        child: Container(
          width: widget.scaleByHeight
              ? (deviceSize.height * widget.designSize.width) /
                  widget.designSize.height
              : deviceSize.width,
          height: deviceSize.height,
          child: widget.builder(_context, widget.child),
        ),
      ),
    );
  }
}
