import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/launcher_colors.dart';

class CustomScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController? horizontalController;
  final ScrollController? verticalController;
  final bool alwaysVisible;

  const CustomScrollbar({super.key, required this.child, this.horizontalController, this.verticalController, this.alwaysVisible = true});

  @override
  State<CustomScrollbar> createState() => _CustomScrollbarState();
}

class _CustomScrollbarState extends State<CustomScrollbar> {
  late ScrollController _horizontalController;
  late ScrollController _verticalController;
  bool _isHorizontalVisible = false;
  bool _isVerticalVisible = false;

  @override
  void initState() {
    super.initState();
    _horizontalController = widget.horizontalController ?? ScrollController();
    _verticalController = widget.verticalController ?? ScrollController();

    _horizontalController.addListener(_updateHorizontalVisibility);
    _verticalController.addListener(_updateVerticalVisibility);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateHorizontalVisibility();
      _updateVerticalVisibility();
    });
  }

  @override
  void dispose() {
    if (widget.horizontalController == null) {
      _horizontalController.dispose();
    }
    if (widget.verticalController == null) {
      _verticalController.dispose();
    }
    super.dispose();
  }

  void _updateHorizontalVisibility() {
    final hasHorizontalScroll = _horizontalController.hasClients && _horizontalController.position.maxScrollExtent > 0;
    if (_isHorizontalVisible != hasHorizontalScroll) {
      setState(() {
        _isHorizontalVisible = hasHorizontalScroll;
      });
    }
  }

  void _updateVerticalVisibility() {
    final hasVerticalScroll = _verticalController.hasClients && _verticalController.position.maxScrollExtent > 0;
    if (_isVerticalVisible != hasVerticalScroll) {
      setState(() {
        _isVerticalVisible = hasVerticalScroll;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          widget.child,
          if (_isVerticalVisible || widget.alwaysVisible)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 12,
                decoration: BoxDecoration(color: LauncherColors.darkGray.withOpacity(0.8), border: Border.all(color: LauncherColors.gold, width: 1)),
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 10,
                  radius: const Radius.circular(6),
                  child: Container(),
                ),
              ),
            ),
          if (_isHorizontalVisible || widget.alwaysVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 12,
                decoration: BoxDecoration(color: LauncherColors.darkGray.withOpacity(0.8), border: Border.all(color: LauncherColors.gold, width: 1)),
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 10,
                  radius: const Radius.circular(6),
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: Container(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft || event.logicalKey == LogicalKeyboardKey.shiftRight) {
        _handleShiftScroll(event);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.pageUp ||
          event.logicalKey == LogicalKeyboardKey.pageDown) {
        _handleVerticalScroll(event);
      }
    }
  }

  void _handleShiftScroll(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft ? -50.0 : 50.0;
      _horizontalController.animateTo(
        (_horizontalController.offset + delta).clamp(0.0, _horizontalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleVerticalScroll(KeyEvent event) {
    double delta = 0;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        delta = -50.0;
        break;
      case LogicalKeyboardKey.arrowDown:
        delta = 50.0;
        break;
      case LogicalKeyboardKey.pageUp:
        delta = -200.0;
        break;
      case LogicalKeyboardKey.pageDown:
        delta = 200.0;
        break;
    }

    if (delta != 0) {
      _verticalController.animateTo(
        (_verticalController.offset + delta).clamp(0.0, _verticalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }
}

class ScrollableArea extends StatefulWidget {
  final Widget child;
  final double? maxWidth;
  final double? maxHeight;

  const ScrollableArea({super.key, required this.child, this.maxWidth, this.maxHeight});

  @override
  State<ScrollableArea> createState() => _ScrollableAreaState();
}

class _ScrollableAreaState extends State<ScrollableArea> {
  late ScrollController _horizontalController;
  late ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollbar(
      horizontalController: _horizontalController,
      verticalController: _verticalController,
      child: SingleChildScrollView(
        controller: _verticalController,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth ?? double.infinity, maxHeight: widget.maxHeight ?? double.infinity),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
