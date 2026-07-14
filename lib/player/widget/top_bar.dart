import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller.dart';
import 'advanced_options_sheet.dart';

class TopBar extends StatelessWidget {
  final IndexPlayerController controller;

  const TopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: controller.isFullScreen.value
          ? EdgeInsets.symmetric(horizontal: 40, vertical: 8)
          : EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
              if (controller.isFullScreen.value) {
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
