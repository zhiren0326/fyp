import 'package:flutter/material.dart';

/// Custom connection quality indicator that creates its own signal bars
class CustomConnectionQualityIndicator extends StatelessWidget {
  final String quality; // 'excellent', 'good', 'fair', 'poor'
  final bool isVisible;

  const CustomConnectionQualityIndicator({
    Key? key,
    required this.quality,
    this.isVisible = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    Color color;
    int bars;

    switch (quality) {
      case 'excellent':
        color = Colors.green;
        bars = 4;
        break;
      case 'good':
        color = Colors.yellow;
        bars = 3;
        break;
      case 'fair':
        color = Colors.orange;
        bars = 2;
        break;
      case 'poor':
        color = Colors.red;
        bars = 1;
        break;
      default:
        color = Colors.grey;
        bars = 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Custom signal bars
          Row(
            children: List.generate(4, (index) {
              return Container(
                width: 3,
                height: 6 + (index * 3),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: index < bars ? color : Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
          const SizedBox(width: 6),
          // Quality text
          Text(
            _getQualityText(quality),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getQualityText(String quality) {
    switch (quality) {
      case 'excellent':
        return 'HD';
      case 'good':
        return 'Good';
      case 'fair':
        return 'Fair';
      case 'poor':
        return 'Poor';
      default:
        return 'No Signal';
    }
  }
}

/// Alternative simple version with just colored dot
class SimpleConnectionIndicator extends StatelessWidget {
  final String quality;
  final bool isVisible;

  const SimpleConnectionIndicator({
    Key? key,
    required this.quality,
    this.isVisible = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    Color color;
    IconData icon;

    switch (quality) {
      case 'excellent':
        color = Colors.green;
        icon = Icons.wifi;
        break;
      case 'good':
        color = Colors.yellow;
        icon = Icons.wifi;
        break;
      case 'fair':
        color = Colors.orange;
        icon = Icons.wifi_2_bar;
        break;
      case 'poor':
        color = Colors.red;
        icon = Icons.wifi_1_bar;
        break;
      default:
        color = Colors.grey;
        icon = Icons.wifi_off;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: color,
        size: 14,
      ),
    );
  }
}

/// Animated connection quality indicator
class AnimatedConnectionIndicator extends StatefulWidget {
  final String quality;
  final bool isVisible;

  const AnimatedConnectionIndicator({
    Key? key,
    required this.quality,
    this.isVisible = true,
  }) : super(key: key);

  @override
  State<AnimatedConnectionIndicator> createState() => _AnimatedConnectionIndicatorState();
}

class _AnimatedConnectionIndicatorState extends State<AnimatedConnectionIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    Color color;
    int bars;

    switch (widget.quality) {
      case 'excellent':
        color = Colors.green;
        bars = 4;
        break;
      case 'good':
        color = Colors.yellow;
        bars = 3;
        break;
      case 'fair':
        color = Colors.orange;
        bars = 2;
        break;
      case 'poor':
        color = Colors.red;
        bars = 1;
        break;
      default:
        color = Colors.grey;
        bars = 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(4, (index) {
              return Container(
                width: 3,
                height: 6 + (index * 3),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: index < bars
                      ? color.withOpacity(_animation.value)
                      : Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}