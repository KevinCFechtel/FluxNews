import 'package:flutter/widgets.dart';

const int _maximumNewsImageCacheDimension = 1200;

int newsImageCacheDimension(BuildContext context, double logicalPixels) {
  return (logicalPixels * MediaQuery.devicePixelRatioOf(context))
      .round()
      .clamp(1, _maximumNewsImageCacheDimension)
      .toInt();
}
