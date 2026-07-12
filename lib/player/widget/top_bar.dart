import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller.dart';

class TopBar extends StatelessWidget {
  final IndexPlayerController controller;

  const TopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        controller.isFullScreen.value ? 8 : 4,
        8,
        16,
        24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.78), Colors.transparent],
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
          const SizedBox(width: 12),
          Expanded(
            child: Obx(
              () => Text(
                controller.video.value?.title ?? "",
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
        ],
      ),
    );
  }
}
