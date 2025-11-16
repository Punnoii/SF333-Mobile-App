import 'package:flutter/material.dart';

class DisabilityTypeOption {
  const DisabilityTypeOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

class DisabilityTypes {
  static const options = <DisabilityTypeOption>[
    DisabilityTypeOption(
      value: 'vision',
      label: 'การมองเห็น',
      icon: Icons.visibility_off,
      color: Colors.deepOrange,
    ),
    DisabilityTypeOption(
      value: 'hearing',
      label: 'การได้ยิน',
      icon: Icons.hearing_disabled,
      color: Colors.blue,
    ),
    DisabilityTypeOption(
      value: 'mobility',
      label: 'การเคลื่อนไหว',
      icon: Icons.wheelchair_pickup,
      color: Colors.green,
    ),
    DisabilityTypeOption(
      value: 'cognitive',
      label: 'การเรียนรู้/สติปัญญา',
      icon: Icons.psychology_alt,
      color: Colors.purple,
    ),
    DisabilityTypeOption(
      value: 'communication',
      label: 'การสื่อสาร/พูด',
      icon: Icons.record_voice_over,
      color: Colors.teal,
    ),
    DisabilityTypeOption(
      value: 'other',
      label: 'อื่นๆ',
      icon: Icons.info_outline,
      color: Colors.grey,
    ),
  ];

  static final Map<String, DisabilityTypeOption> _byValue = {
    for (final option in options) option.value: option,
  };

  static DisabilityTypeOption? get(String? value) => _byValue[value];

  static String label(String value) => _byValue[value]?.label ?? value;
}
