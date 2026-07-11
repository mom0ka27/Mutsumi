import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller.dart';

class TopBar extends StatelessWidget {
  final IndexPlayerController controller;

  const TopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () async {
            // await widget.controller.exitFullscreen();
            Get.back();
          },
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        SizedBox(width: 10),
        Obx(
          () => Text(
            controller.video.value?.title ?? "",
            style: TextStyle(color: Colors.white),
          ),
        ),
        Spacer(),
      ],
    );
  }
}
