import 'package:flutter/material.dart';

class CompactModeSwitch extends StatelessWidget {
  const CompactModeSwitch({
    required this.onlineSelected,
    required this.onChanged,
    super.key,
  });

  final bool onlineSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      segments: const [
        ButtonSegment<bool>(
          value: false,
          label: Text('Local'),
          icon: Icon(Icons.smart_toy_outlined, size: 16),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('Online'),
          icon: Icon(Icons.wifi, size: 16),
        ),
      ],
      selected: <bool>{onlineSelected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
