import 'dart:math' show min, max;
import 'dart:async' show Completer;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Result of applying a new group of screen metrics.
///
/// [deferred] means the candidate belongs to an incomplete fold transition and
/// the previous narrow adaptation width is still in use.
enum ScreenMetricsUpdateStatus { changed, unchanged, deferred, uninitialized }

class ScreenUtil with WidgetsBindingObserver {
  static const Size defaultSize = Size(360, 690);
  static const double _phoneShortestSideBreakpoint = 600;
  static const double _wideFoldMinAspectRatio = 0.65;
  static ScreenUtil _instance = ScreenUtil._();

  /// UI设计中手机尺寸 , dp
  /// Size of the phone in UI Design , dp
  late Size _uiSize;
  late Size _unfoldedUiSize;

  ///屏幕方向
  late Orientation _orientation;

  late double _foldedScreenWidth;
  Orientation? _foldedScreenWidthOrientation;
  late double _unfoldedScreenWidth;
  double? _prefetchedFoldedScreenWidth;
  late bool _minTextAdapt;
  late bool _splitScreenMode;
  bool _enableFoldWidthAdaptation = true;
  BuildContext? _context;
  Size _viewportSize = Size.zero;
  bool _isInitialized = false;
  bool _isObservingMetrics = false;
  bool _metricsUpdateScheduled = false;
  bool _hasObservedFoldFeature = false;
  bool _hasObservedWideFoldFeature = false;
  bool _hasObservedFoldedViewport = false;
  bool _hasMeasuredFoldedScreenWidth = false;
  bool _hasMeasuredUnfoldedScreenWidth = false;
  bool _isFoldOpen = false;
  bool _isExpandingBeforeFoldFeature = false;

  ScreenUtil._();

  factory ScreenUtil() {
    return _instance;
  }

  /// Manually wait for window size to be initialized
  ///
  /// `Recommended` to use before you need access window size
  /// or in custom splash/bootstrap screen [FutureBuilder]
  ///
  /// example:
  /// ```dart
  /// ...
  /// ScreenUtil.init(context, ...);
  /// ...
  ///   FutureBuilder(
  ///     future: Future.wait([..., ensureScreenSize(), ...]),
  ///     builder: (context, snapshot) {
  ///       if (snapshot.hasData) return const HomeScreen();
  ///       return Material(
  ///         child: LayoutBuilder(
  ///           ...
  ///         ),
  ///       );
  ///     },
  ///   )
  /// ```
  // static Future<void> ensureScreenSize([
  //   FlutterView? window,
  //   Duration duration = const Duration(milliseconds: 10),
  // ]) async {
  //   final binding = WidgetsFlutterBinding.ensureInitialized();
  //   window ??= WidgetsBinding.instance.platformDispatcher.implicitView;

  //   if (window?.physicalGeometry.isEmpty == true) {
  //     return Future.delayed(duration, () async {
  //       binding.deferFirstFrame();
  //       await ensureScreenSize(window, duration);
  //       return binding.allowFirstFrame();
  //     });
  //   }
  // }
  static Future<void> ensureScreenSize(
    BuildContext context, [
    Duration duration = const Duration(milliseconds: 10),
  ]) async {
    final binding = WidgetsFlutterBinding.ensureInitialized();

    var windowSize = MediaQuery.of(context).size;

    if (windowSize.isEmpty) {
      return Future.delayed(duration, () async {
        binding.deferFirstFrame();
        await ensureScreenSize(context, duration);
        return binding.allowFirstFrame();
      });
    }
  }

  Set<Element>? _elementsToRebuild;

  /// ### Experimental
  /// Register current page and all its descendants to rebuild.
  /// Helpful when building for web and desktop
  static void registerToBuild(
    BuildContext context, [
    bool withDescendants = false,
  ]) {
    (_instance._elementsToRebuild ??= {}).add(context as Element);

    if (withDescendants) {
      context.visitChildren((element) {
        registerToBuild(element, true);
      });
    }
  }

  /// Initializing the library.
  ///
  /// When [enableFoldWidthAdaptation] is true (the default), unfolded foldable
  /// displays keep a narrow width scale instead of scaling from the full
  /// two-pane viewport. Set it to false to retain the standard viewport-based
  /// `.w/.sp` behavior while still collecting fold metrics.
  static Future<void> init(
    BuildContext context, {
    Size designSize = defaultSize,
    Size? unfoldedDesignSize,
    double? foldedScreenWidth,
    bool splitScreenMode = false,
    bool minTextAdapt = false,
    bool scaleByHeight = false,
    bool enableFoldWidthAdaptation = true,
  }) async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final mediaQueryContext =
        context.getElementForInheritedWidgetOfExactType<MediaQuery>();
    final initCompleter = Completer<void>();

    binding.addPostFrameCallback((_) {
      if (!scaleByHeight) {
        mediaQueryContext?.visitChildElements((el) => _instance._context = el);
      }
      if (!initCompleter.isCompleted) initCompleter.complete();
    });

    final mediaQuery = MediaQuery.of(context);
    final validFoldedScreenWidth = foldedScreenWidth != null &&
            foldedScreenWidth.isFinite &&
            foldedScreenWidth > 0
        ? foldedScreenWidth
        : null;

    _instance
      .._context = scaleByHeight ? null : context
      .._uiSize = designSize
      .._unfoldedUiSize = unfoldedDesignSize ?? designSize
      .._prefetchedFoldedScreenWidth = validFoldedScreenWidth
      .._minTextAdapt = minTextAdapt
      .._splitScreenMode = splitScreenMode
      .._enableFoldWidthAdaptation = enableFoldWidthAdaptation
      .._isInitialized = true;

    if (validFoldedScreenWidth != null &&
        (!_instance._hasObservedFoldedViewport ||
            _instance._foldedScreenWidthOrientation !=
                mediaQuery.orientation)) {
      _instance
        .._foldedScreenWidth = validFoldedScreenWidth
        .._foldedScreenWidthOrientation = mediaQuery.orientation
        .._hasMeasuredFoldedScreenWidth = true;
    }

    _instance._commitScreenMetrics(
      mediaQuery.size,
      mediaQuery.orientation,
      mediaQuery.displayFeatures,
    );
    _instance._ensureMetricsObserver(binding);

    _instance._markRegisteredElementsNeedsBuild();

    return initCompleter.future;
  }

  /// Recalculates the cached screen metrics while preserving the design
  /// configuration passed to [init].
  ///
  /// Folded layouts use the latest stable viewport width. Unfolded layouts
  /// keep the scale reference selected when the unfolded state first appears.
  static ScreenMetricsUpdateStatus updateMetrics(BuildContext context) {
    if (!_instance._isInitialized) {
      return ScreenMetricsUpdateStatus.uninitialized;
    }
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null || mediaQuery.size.isEmpty) {
      return ScreenMetricsUpdateStatus.deferred;
    }

    _instance._context = context;
    return _instance._commitScreenMetrics(
      mediaQuery.size,
      mediaQuery.orientation,
      mediaQuery.displayFeatures,
    );
  }

  /// Compatibility entry point for applications that may also be built with
  /// an older package revision.
  ///
  /// Callers can invoke this instance method through `dynamic`: a revision
  /// without this method then raises [NoSuchMethodError], allowing the caller
  /// to fall back without referring to custom static APIs or enum types.
  /// Returns null until [init] has completed.
  bool? syncFoldMetrics(BuildContext context) {
    final status = ScreenUtil.updateMetrics(context);
    return status == ScreenMetricsUpdateStatus.uninitialized
        ? null
        : _isFoldOpen;
  }

  void _ensureMetricsObserver(WidgetsBinding binding) {
    if (_isObservingMetrics) return;
    binding.addObserver(this);
    _isObservingMetrics = true;
  }

  ScreenMetricsUpdateStatus _commitScreenMetrics(
    Size size,
    Orientation orientation,
    List<ui.DisplayFeature> displayFeatures,
  ) {
    if (size.isEmpty || size.width <= 0 || size.height <= 0) {
      return ScreenMetricsUpdateStatus.deferred;
    }

    final rawFoldFeatures = displayFeatures.where(_isFoldFeature);
    final usableFoldFeatures = _usableFoldFeatures(size, displayFeatures);
    if (rawFoldFeatures.isNotEmpty && usableFoldFeatures.isEmpty) {
      // fold bounds 还属于上一个 viewport，不能拿来推算 pane 宽度。
      return ScreenMetricsUpdateStatus.deferred;
    }

    _syncUiSizeForOrientation(orientation);

    final hasFoldFeature = usableFoldFeatures.isNotEmpty;
    if (hasFoldFeature) _hasObservedFoldFeature = true;
    final wideFoldFeatures = usableFoldFeatures
        .where((feature) => _isWideBookFoldFeature(size, orientation, feature))
        .toList(growable: false);
    final hasWideFoldFeature = wideFoldFeatures.isNotEmpty;
    final prefetchedFoldedScreenWidth = _prefetchedFoldedScreenWidth;
    final hadPreviousMetrics = _viewportSize != Size.zero;
    final paneScreenWidth = _screenWidthForDisplayFeatures(
      size,
      wideFoldFeatures,
    );

    final samePortraitOrientation = hadPreviousMetrics &&
        orientation == Orientation.portrait &&
        _orientation == Orientation.portrait;
    final startsExpandingBeforeFoldFeature = hadPreviousMetrics &&
        !_isFoldOpen &&
        size.width > _foldedScreenWidth + 1 &&
        size.width > _viewportSize.width + 1;

    // 已确认过真实收合 viewport 后，只要直向宽度开始大于收合实宽，
    // 就代表收合 -> 展开的动画已经开始。此时 viewport 通常早于 fold feature
    // 抵达；必须在第一帧先切换到展开设计稿，避免外层已移位、内部 `.w/.sp`
    // 却仍按收合设计稿放大的混合状态。
    if (!hasWideFoldFeature &&
        !hasFoldFeature &&
        samePortraitOrientation &&
        _hasObservedFoldedViewport &&
        _foldedScreenWidthOrientation == orientation &&
        size.width > _foldedScreenWidth + 1 &&
        (_isExpandingBeforeFoldFeature || startsExpandingBeforeFoldFeature)) {
      final changed =
          _viewportSize != size || _orientation != orientation || !_isFoldOpen;

      _unfoldedScreenWidth = size.width;
      _hasMeasuredUnfoldedScreenWidth = true;
      _viewportSize = size;
      _orientation = orientation;
      _isFoldOpen = true;
      _isExpandingBeforeFoldFeature = true;
      return changed
          ? ScreenMetricsUpdateStatus.changed
          : ScreenMetricsUpdateStatus.unchanged;
    }

    if (!hasWideFoldFeature && !hasFoldFeature && hadPreviousMetrics) {
      final widthGrowthReference = _hasObservedWideFoldFeature
          ? _foldedScreenWidth
          : _viewportSize.width;
      final widthGrowthThreshold = max(
        widthGrowthReference * 1.35,
        widthGrowthReference + 120,
      );

      // 展开 viewport 比 fold feature 先到时，保留既有窄宽度，不发布全宽。
      if (!_isFoldOpen &&
          samePortraitOrientation &&
          size.width >= widthGrowthThreshold) {
        return ScreenMetricsUpdateStatus.deferred;
      }

      if (_isFoldOpen && samePortraitOrientation) {
        final foldedReference = _foldedScreenWidth;
        // 收合时 feature 可能先消失；只有 viewport 已接近预估／实测的
        // 收合宽度才视为真的收合完成。
        if (size.width > foldedReference * 1.35) {
          return ScreenMetricsUpdateStatus.deferred;
        }
      }
    }

    bool effectiveFoldOpen;
    if (hasWideFoldFeature) {
      _isExpandingBeforeFoldFeature = false;
      if (!_hasObservedWideFoldFeature) {
        final previousWasRealFoldedViewport =
            hadPreviousMetrics && _viewportSize.width < size.width * 0.8;
        if (previousWasRealFoldedViewport) {
          _foldedScreenWidth = _viewportSize.width;
          _foldedScreenWidthOrientation = orientation;
          _hasMeasuredFoldedScreenWidth = true;
          _hasObservedFoldedViewport = true;
        } else if (prefetchedFoldedScreenWidth != null) {
          // App 冷启动就在展开态时，优先使用原生层预取的外屏实际宽度。
          _foldedScreenWidth = prefetchedFoldedScreenWidth;
          _foldedScreenWidthOrientation = orientation;
          _hasMeasuredFoldedScreenWidth = true;
        } else {
          // App 冷启动就在展开态：先用系统切出的最窄 pane 预估收合宽度。
          _foldedScreenWidth = paneScreenWidth;
          _foldedScreenWidthOrientation = orientation;
          _hasMeasuredFoldedScreenWidth = false;
        }
        _hasObservedWideFoldFeature = true;
      } else if (!_hasMeasuredFoldedScreenWidth) {
        // 尚未真的收合前，fold bounds 若仍在变动只保留观测过的最窄 pane。
        _foldedScreenWidth = _foldedScreenWidthOrientation == orientation
            ? min(_foldedScreenWidth, paneScreenWidth)
            : paneScreenWidth;
        _foldedScreenWidthOrientation = orientation;
      }

      _unfoldedScreenWidth = size.width;
      _hasMeasuredUnfoldedScreenWidth = true;
      effectiveFoldOpen = true;
    } else if (_hasObservedWideFoldFeature) {
      // 真正收合后，每次稳定 metrics 都使用当下 viewport 的实际宽度。
      _isExpandingBeforeFoldFeature = false;
      _foldedScreenWidth = size.width;
      _foldedScreenWidthOrientation = orientation;
      _hasMeasuredFoldedScreenWidth = true;
      _hasObservedFoldedViewport = true;
      effectiveFoldOpen = false;
    } else if (prefetchedFoldedScreenWidth != null) {
      final unfoldedThreshold = max(
        prefetchedFoldedScreenWidth * 1.35,
        prefetchedFoldedScreenWidth + 120,
      );
      if (size.width >= unfoldedThreshold) {
        // 原生层已确认存在独立外屏，但首帧 fold feature 尚未送达。
        // 先发布展开状态，避免 `.w/.sp` 在首帧使用收合设计稿而放大。
        _foldedScreenWidth = prefetchedFoldedScreenWidth;
        _foldedScreenWidthOrientation = orientation;
        _unfoldedScreenWidth = size.width;
        _hasMeasuredFoldedScreenWidth = true;
        _hasMeasuredUnfoldedScreenWidth = true;
        effectiveFoldOpen = true;
        _isExpandingBeforeFoldFeature = true;
      } else {
        // 收合状态以 Flutter 实际 viewport 为最终权威值。
        _isExpandingBeforeFoldFeature = false;
        _foldedScreenWidth = size.width;
        _foldedScreenWidthOrientation = orientation;
        _unfoldedScreenWidth = size.width;
        _hasMeasuredFoldedScreenWidth = true;
        _hasObservedFoldedViewport = true;
        effectiveFoldOpen = false;
      }
    } else {
      // 一般装置没有折叠证据，实际 viewport 就是唯一的宽度。
      _isExpandingBeforeFoldFeature = false;
      _foldedScreenWidth = size.width;
      _foldedScreenWidthOrientation = orientation;
      _unfoldedScreenWidth = size.width;
      effectiveFoldOpen = false;
    }

    final changed = _viewportSize == Size.zero ||
        _viewportSize != size ||
        _orientation != orientation ||
        _isFoldOpen != effectiveFoldOpen;

    _viewportSize = size;
    _orientation = orientation;
    _isFoldOpen = effectiveFoldOpen;
    return changed
        ? ScreenMetricsUpdateStatus.changed
        : ScreenMetricsUpdateStatus.unchanged;
  }

  void _syncUiSizeForOrientation(Orientation orientation) {
    final uiSizeIsLandscape = _uiSize.width > _uiSize.height;
    final viewportIsLandscape = orientation == Orientation.landscape;
    if (_uiSize.width == _uiSize.height ||
        uiSizeIsLandscape == viewportIsLandscape) {
      return;
    }

    _uiSize = Size(_uiSize.height, _uiSize.width);
  }

  bool _isFoldFeature(ui.DisplayFeature feature) =>
      feature.type == ui.DisplayFeatureType.fold ||
      feature.type == ui.DisplayFeatureType.hinge;

  List<ui.DisplayFeature> _usableFoldFeatures(
    Size size,
    List<ui.DisplayFeature> displayFeatures,
  ) {
    return displayFeatures.where(_isFoldFeature).where((feature) {
      final bounds = feature.bounds;
      final left = bounds.left.clamp(0.0, size.width).toDouble();
      final top = bounds.top.clamp(0.0, size.height).toDouble();
      final right = bounds.right.clamp(0.0, size.width).toDouble();
      final bottom = bounds.bottom.clamp(0.0, size.height).toDouble();

      final isVertical = bounds.height >= size.height * 0.5 &&
          bounds.width <= size.width * 0.25;
      if (isVertical) {
        return left >= size.width * 0.2 &&
            size.width - right >= size.width * 0.2;
      }

      final isHorizontal = bounds.width >= size.width * 0.5 &&
          bounds.height <= size.height * 0.25;
      if (isHorizontal) {
        return top >= size.height * 0.1 &&
            size.height - bottom >= size.height * 0.1;
      }
      return false;
    }).toList(growable: false);
  }

  /// 只有书本式左右展开、且 viewport 已接近宽版比例时，才套用展开设计稿。
  ///
  /// 直向书本式装置的折线会垂直分隔左右 pane；旋转为横向后则会变成
  /// 水平分隔。Flip 类上下折装置刚好相反，因此不会误用 1500 宽设计稿。
  bool _isWideBookFoldFeature(
    Size size,
    Orientation orientation,
    ui.DisplayFeature feature,
  ) {
    final normalizedAspectRatio = size.shortestSide / size.longestSide;
    if (normalizedAspectRatio < _wideFoldMinAspectRatio) return false;

    final bounds = feature.bounds;
    final isVertical =
        bounds.height >= size.height * 0.5 && bounds.width <= size.width * 0.25;
    final isHorizontal =
        bounds.width >= size.width * 0.5 && bounds.height <= size.height * 0.25;

    return orientation == Orientation.portrait ? isVertical : isHorizontal;
  }

  double _screenWidthForDisplayFeatures(
    Size size,
    List<ui.DisplayFeature> displayFeatures,
  ) {
    final foldBounds = displayFeatures.map((feature) {
      final bounds = feature.bounds;
      // 折叠动画期间 size 与 feature 可能分两次抵达，先限制在本帧 viewport，
      // 避免短暂使用下一帧座标算出比目前视窗还大的 pane。
      return Rect.fromLTRB(
        bounds.left.clamp(0.0, size.width).toDouble(),
        bounds.top.clamp(0.0, size.height).toDouble(),
        bounds.right.clamp(0.0, size.width).toDouble(),
        bounds.bottom.clamp(0.0, size.height).toDouble(),
      );
    });
    if (foldBounds.isEmpty) return size.width;

    final subScreens = DisplayFeatureSubScreen.subScreensInBounds(
      Offset.zero & size,
      foldBounds,
    );
    final paneWidths = subScreens
        .map((subScreen) => subScreen.width)
        .where((width) => width > 0);
    if (paneWidths.isEmpty) return size.width;

    // 垂直 fold/hinge 会产生左右 pane，使用较窄的实际 pane，确保所有内容都放得下。
    // 水平 fold/hinge 产生的上下 pane 宽度都等于视窗宽度，因此不影响 .w。
    return paneWidths.reduce(min);
  }

  @override
  void didChangeMetrics() {
    if (!_isInitialized) return;

    // FlutterView 的新尺寸会早于 inherited MediaQuery 对应的重建抵达。
    // 先同步原始 view metrics，让同一轮 didChangeMetrics 中较晚执行的
    // 弹窗／页面 observer 在重建 `.w/.sp` 时已经取得正确比例。
    final context = _context;
    final view = context != null && context.mounted
        ? View.maybeOf(context)
        : WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      final viewMediaQuery = MediaQueryData.fromView(view);
      final status = _commitScreenMetrics(
        viewMediaQuery.size,
        viewMediaQuery.orientation,
        viewMediaQuery.displayFeatures,
      );
      if (status == ScreenMetricsUpdateStatus.changed) {
        _markRegisteredElementsNeedsBuild();
      }
    }

    if (_metricsUpdateScheduled) return;
    _metricsUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsUpdateScheduled = false;
      final context = _context;
      if (context == null || !context.mounted) return;

      // 由 inherited MediaQuery 更新 viewport、fold feature 与实测宽度。
      final status = ScreenUtil.updateMetrics(context);
      if (status != ScreenMetricsUpdateStatus.changed) return;
      _markRegisteredElementsNeedsBuild();
    });
  }

  void _markRegisteredElementsNeedsBuild() {
    final elements = _elementsToRebuild;
    if (elements == null) return;
    elements.removeWhere((element) => !element.mounted);
    for (final element in elements) {
      element.markNeedsBuild();
    }
  }

  static void setContext(BuildContext context) {
    _instance._context = context;
  }

  ///获取屏幕方向
  ///Get screen orientation
  Orientation get orientation => _orientation;

  /// 每个逻辑像素的字体像素数，字体的缩放比例
  /// The number of font pixels for each logical pixel.
  double get textScaleFactor {
    final context = _context;
    if (context == null || !context.mounted) return 1.0;
    return MediaQuery.textScalerOf(context).scale(1.0);
  }

  /// 设备的像素密度
  /// The size of the media in logical pixels (e.g, the size of the screen).
  double? get pixelRatio {
    final context = _context;
    if (context == null || !context.mounted) return 1;
    return MediaQuery.devicePixelRatioOf(context);
  }

  /// 当前设备宽度 dp
  ///
  /// 启用折叠适配且当前为展开态时，返回收合设计稿宽度经当前 `.w`
  /// 比例换算后的 pane 实际宽度。这样使用 [screenWidth] 排版的单栏内容会与
  /// 展开设计稿共用同一套比例；原生预取的收合实宽仍由 [foldedScreenWidth]
  /// 提供。
  ///
  /// 收合态与一般装置维持原行为，返回当前或已确认的收合实际宽度；完整的
  /// 当前视窗宽度请使用 [viewportWidth]。
  double get screenWidth {
    if (!_enableFoldWidthAdaptation) return viewportWidth;
    if (_isFoldOpen) return setWidth(_uiSize.width);
    if (_prefetchedFoldedScreenWidth != null || _hasObservedFoldFeature) {
      return _foldedScreenWidth;
    }
    return viewportWidth;
  }

  /// 目前 FlutterView 的完整逻辑宽度，不套用 fold/hinge 分割。
  double get viewportWidth => _viewportSize.width;

  ///当前设备高度 dp
  ///The vertical extent of this size. dp
  double get screenHeight => _viewportSize.height;

  /// 已确认的折叠收合逻辑宽度。
  ///
  /// 折叠机尚未实际观测到收合态时，回退为展开态的最窄 pane 宽度。
  /// 非折叠装置永远等于 [screenWidth]。
  double get foldedScreenWidth => _foldedScreenWidth;

  /// 已确认的折叠展开逻辑宽度。
  ///
  /// 折叠机尚未实际观测到展开态时，回退为目前视窗宽度，不做倍数推算。
  /// 非折叠装置永远等于 [screenWidth]。
  double get unfoldedScreenWidth => _unfoldedScreenWidth;

  /// 是否曾从系统取得 fold/hinge display feature。
  bool get hasObservedFoldFeature => _hasObservedFoldFeature;

  /// Whether [init] has produced the first usable metrics snapshot.
  bool get isInitialized => _isInitialized;

  /// 目前是否为可套用宽版设计稿的书本式折叠展开状态。
  bool get isFoldOpen => _isFoldOpen;

  /// 是否启用折叠展开时的窄版 `.w/.sp` 缩放修正。
  bool get enableFoldWidthAdaptation => _enableFoldWidthAdaptation;

  /// 是否已实际观测过折叠收合与展开两种宽度。
  bool get hasMeasuredBothFoldWidths =>
      _hasMeasuredFoldedScreenWidth && _hasMeasuredUnfoldedScreenWidth;

  /// 旧 API 相容别名；展开宽度请优先使用 [unfoldedScreenWidth]。
  double get flipScreenWidth => unfoldedScreenWidth;

  /// 状态栏高度 dp 刘海屏会更高
  /// The offset from the top, in dp
  double get statusBarHeight => _context == null || !_context!.mounted
      ? 0
      : MediaQuery.of(_context!).padding.top;

  /// 底部安全区距离 dp
  /// The offset from the bottom, in dp
  double get bottomBarHeight => _context == null || !_context!.mounted
      ? 0
      : MediaQuery.of(_context!).padding.bottom;

  /// 实际尺寸与UI设计的比例
  /// The ratio of actual width to UI design.
  ///
  /// 收合态依 `designSize`，展开态依 `unfoldedDesignSize` 计算；两种状态
  /// 不共享实测缩放基准，因此启动路径不会改变 `.w/.sp` 的结果。
  double get scaleWidth {
    if (_usesLegacyPhoneLandscapeScale) {
      return _viewportSize.shortestSide / _uiSize.shortestSide;
    }

    final designWidth = _enableFoldWidthAdaptation && _isFoldOpen
        ? _unfoldedUiSize.width
        : _uiSize.width;
    return viewportWidth / designWidth;
  }

  /// 一般手机横屏沿用旧版旋转前的直屏宽度比例。
  ///
  /// `shortestSide < 600` 只用于区分手机与平板，不参与折叠状态判断；目前
  /// 处于折叠展开态时，仍以折叠设计稿的规则计算。
  bool get _usesLegacyPhoneLandscapeScale =>
      _orientation == Orientation.landscape &&
      !_isFoldOpen &&
      _prefetchedFoldedScreenWidth == null &&
      _viewportSize.shortestSide < _phoneShortestSideBreakpoint;

  ///  /// The ratio of actual height to UI design
  double get scaleHeight =>
      (_splitScreenMode ? max(screenHeight, 700) : screenHeight) /
      _uiSize.height;

  double get scaleText =>
      _minTextAdapt ? min(scaleWidth, scaleHeight) : scaleWidth;

  double get marginBorderWidth =>
      _isFoldOpen ? max(0.0, (viewportWidth - screenWidth) / 2) : 0.0;

  /// 根据UI设计的设备宽度适配
  /// 高度也可以根据这个来做适配可以保证不变形,比如你想要一个正方形的时候.
  /// Adapted to the device width of the UI Design.
  /// Height can also be adapted according to this to ensure no deformation ,
  /// if you want a square
  double setWidth(num width) => width * scaleWidth;

  /// 根据UI设计的设备高度适配
  /// 当发现UI设计中的一屏显示的与当前样式效果不符合时,
  /// 或者形状有差异时,建议使用此方法实现高度适配.
  /// 高度适配主要针对想根据UI设计的一屏展示一样的效果
  /// Highly adaptable to the device according to UI Design
  /// It is recommended to use this method to achieve a high degree of adaptation
  /// when it is found that one screen in the UI design
  /// does not match the current style effect, or if there is a difference in shape.
  double setHeight(num height) => height * scaleHeight;

  ///根据宽度或高度中的较小值进行适配
  ///Adapt according to the smaller of width or height
  double radius(num r) => r * min(scaleWidth, scaleHeight);

  ///字体大小适配方法
  ///- [fontSize] UI设计上字体的大小,单位dp.
  ///Font size adaptation method
  ///- [fontSize] The size of the font on the UI design, in dp.
  double setSp(num fontSize) => fontSize * scaleText;

  Widget setVerticalSpacing(num height) => SizedBox(height: setHeight(height));

  Widget setVerticalSpacingFromWidth(num height) =>
      SizedBox(height: setWidth(height));

  Widget setHorizontalSpacing(num width) => SizedBox(width: setWidth(width));

  Widget setHorizontalSpacingRadius(num width) =>
      SizedBox(width: radius(width));

  Widget setVerticalSpacingRadius(num height) =>
      SizedBox(height: radius(height));
}

// extension on MediaQueryData? {
//   MediaQueryData? nonEmptySizeOrNull() {
//     if (this?.size.isEmpty ?? true)
//       return null;
//     else
//       return this;
//   }
// }
