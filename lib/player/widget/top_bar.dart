import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller.dart';
import 'advanced_options_sheet.dart';

class TopBar extends StatelessWidget {
  final IndexPlayerController controller;
  final bool closePageOnBack;

  const TopBar({
    super.key,
    required this.controller,
    this.closePageOnBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.viewPaddingOf(context);
    final horizontalPadding = controller.isFullScreen.value
        ? EdgeInsets.only(
            left: safeArea.left.clamp(40.0, double.infinity).toDouble(),
            right: safeArea.right.clamp(40.0, double.infinity).toDouble(),
            top: safeArea.top.clamp(8.0, double.infinity).toDouble(),
            bottom: 8,
          )
        : const EdgeInsets.symmetric(horizontal: 4, vertical: 4);
    return Container(
      padding: horizontalPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.64), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              if (closePageOnBack) {
                Get.back();
              } else if (controller.isFullScreen.value) {
                await controller.exitFullscreen();
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Obx(
              () => Text(
                "${controller.video.value != null ? controller.video.value!.index.toString().padLeft(2, "0") : ""}   ${controller.video.value?.title ?? "Unknown"}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(blurRadius: 8)],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AdvancedOptionsSheet(controller: controller),
              );
            },
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: '高级选项',
          ),
        ],
      ),
    );
  }
}
