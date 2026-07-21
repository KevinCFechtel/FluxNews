import 'package:flutter/widgets.dart';

const int _maximumNewsImageCacheDimension = 1200;

/// Positions the cover crop at 38.2% of the image height from the top.
const Alignment newsImageCropAlignment = Alignment(0, -0.2360679774997897);

int newsImageCacheDimension(BuildContext context, double logicalPixels) {
  return (logicalPixels * MediaQuery.devicePixelRatioOf(context))
      .round()
      .clamp(1, _maximumNewsImageCacheDimension)
      .toInt();
}
