import 'dart:async';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, Mode, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models_new/dynamic/dyn_mention/item.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_mixin.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/reply_scheme_helper.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show BoxConstraints, WidgetsBinding;
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with
        ReplyVoteMixin,
        GetSingleTickerProviderStateMixin,
        ReplyLocateMixin,
        MainReplyLocateMixin {
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

  MentionItem? get mentionItem {
    if (videoCtr.isUgc) {
      try {
        return videoCtr.ugcIntroCtr.videoDetail.value.owner?.mentionItem;
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }
    return null;
  }

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  void onAnimRootReply(ReplyInfo rootReply) {
    if (args[secondRpIdKey] case final int secondRpId) {
      clearTargetRootRpId();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => replyReply(rootReply, secondRpId),
      );
    } else {
      super.onAnimRootReply(rootReply);
    }
  }

  void replyReply(ReplyInfo replyItem, int? id) {
    videoCtr.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => VideoReplyReplyPanel(
        id: id,
        oid: replyItem.oid.toInt(),
        rpid: replyItem.id.toInt(),
        firstFloor: replyItem.replyControl.isNote ? null : replyItem,
        replyType: videoCtr.videoType.replyType,
        isVideoDetail: true,
        isNested: videoCtr.scrollKey.currentContext != null,
        upMid: upMid,
      ),
    );
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
    rpid: rootRpId,
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
