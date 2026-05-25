import 'package:photo_manager/photo_manager.dart';

enum Decision { pending, keep, delete }

class PhotoItem {
  final AssetEntity entity;
  Decision decision;

  PhotoItem(this.entity, {this.decision = Decision.pending});
}
