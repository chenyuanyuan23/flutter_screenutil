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
  });
}
