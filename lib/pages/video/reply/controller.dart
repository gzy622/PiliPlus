import 'dart:async';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, Mode, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply> {
  static const int previewReplyLimit = 5;

  VideoReplyController({
    required this.aid,
    required this.videoType,
    required this.heroTag,
  });
  int aid;
  final VideoType videoType;
  late final isPugv = videoType == VideoType.pugv;
  final Set<int> _previewRequested = <int>{};

  final String heroTag;
  late final videoCtr = Get.find<VideoDetailController>(tag: heroTag);

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
    type: videoType.replyType,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );

  void ensureReplyPreview(ReplyInfo replyItem) {
    if (replyItem.count.toInt() <= replyItem.replies.length ||
        replyItem.replies.length >= previewReplyLimit) {
      return;
    }

    final root = replyItem.id.toInt();
    if (!_previewRequested.add(root)) {
      return;
    }
    unawaited(_loadReplyPreview(replyItem, root));
  }

  Future<void> _loadReplyPreview(ReplyInfo replyItem, int root) async {
    final result = await ReplyGrpc.detailList(
      type: videoType.replyType,
      oid: replyItem.oid.toInt(),
      root: root,
      rpid: 0,
      mode: Mode.MAIN_LIST_TIME,
      offset: null,
      pageSize: previewReplyLimit,
    );
    if (result case Success(:final response)) {
      final currentList = loadingState.value.dataOrNull;
      if (currentList == null ||
          !currentList.any((item) => identical(item, replyItem))) {
        return;
      }

      final repliesById = <int, ReplyInfo>{};
      for (final reply in response.root.replies) {
        repliesById[reply.id.toInt()] = reply;
      }
      for (final reply in replyItem.replies) {
        repliesById.putIfAbsent(reply.id.toInt(), () => reply);
      }
      replyItem.replies
        ..clear()
        ..addAll(repliesById.values.take(previewReplyLimit));
      loadingState.refresh();
    }
  }

  @override
  Future<void> onRefresh() {
    _previewRequested.clear();
    return super.onRefresh();
  }
}
