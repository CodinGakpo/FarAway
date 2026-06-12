import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/shipment_provider.dart';
import 'available_trucks_screen.dart';

const _categories = [
  'Electronics',
  'Furniture',
  'Machinery',
  'Documents',
  'Consumer Goods',
  'Textile',
  'Construction Material',
  'Other',
];

class ShipmentDetailsScreen extends StatefulWidget {
  const ShipmentDetailsScreen({super.key});

  @override
  State<ShipmentDetailsScreen> createState() =>
      _ShipmentDetailsScreenState();
}

class _ShipmentDetailsScreenState extends State<ShipmentDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();

  String _selectedCategory = _categories[0];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _valueCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  double get _volume {
    final l = double.tryParse(_lengthCtrl.text) ?? 0;
    final w = double.tryParse(_widthCtrl.text) ?? 0;
    final h = double.tryParse(_heightCtrl.text) ?? 0;
    return l * w * h;
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;
    context.read<ShipmentProvider>().updateCargoDetails(
          cargoName: _nameCtrl.text.trim(),
          cargoCategory: _selectedCategory,
          weightKg: double.parse(_weightCtrl.text),
          lengthCm: double.tryParse(_lengthCtrl.text) ?? 0,
          widthCm: double.tryParse(_widthCtrl.text) ?? 0,
          heightCm: double.tryParse(_heightCtrl.text) ?? 0,
          declaredValue: double.tryParse(_valueCtrl.text) ?? 0,
          specialInstructions: _instructionsCtrl.text.trim(),
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AvailableTrucksScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shipment Details'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionLabel('Cargo Information'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Cargo Name *',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            _CategoryPicker(
              value: _selectedCategory,
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Weight & Dimensions'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _weightCtrl,
              decoration: const InputDecoration(
                labelText: 'Weight (kg) *',
                prefixIcon: Icon(Icons.scale_outlined, size: 20),
                suffixText: 'kg',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final n = double.tryParse(v);
                if (n == null || n <= 0) return 'Enter a valid weight';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DimField(
                      ctrl: _lengthCtrl, label: 'Length', onChanged: () => setState(() {})),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DimField(
                      ctrl: _widthCtrl, label: 'Width', onChanged: () => setState(() {})),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DimField(
                      ctrl: _heightCtrl, label: 'Height', onChanged: () => setState(() {})),
                ),
              ],
            ),
            if (_volume > 0) ...[
              const SizedBox(height: 10),
              _VolumeChip(volumeCm3: _volume),
            ],
            const SizedBox(height: 20),
            _SectionLabel('Financial & Instructions'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _valueCtrl,
              decoration: const InputDecoration(
                labelText: 'Declared Value (₹)',
                prefixIcon: Icon(Icons.currency_rupee, size: 20),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructionsCtrl,
              decoration: const InputDecoration(
                labelText: 'Special Instructions',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(Icons.notes_outlined, size: 20),
                ),
                hintText: 'Fragile, keep upright, temperature-sensitive…',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ElevatedButton(
            onPressed: _proceed,
            child: const Text('Find Available Trucks'),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'Cargo Category *',
        prefixIcon: Icon(Icons.category_outlined, size: 20),
      ),
      items: _categories
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      borderRadius: BorderRadius.circular(12),
    );
  }
}

class _DimField extends StatelessWidget {
  const _DimField(
      {required this.ctrl, required this.label, required this.onChanged});
  final TextEditingController ctrl;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: '$label (cm)',
        suffixText: 'cm',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
      ],
      onChanged: (_) => onChanged(),
    );
  }
}

class _VolumeChip extends StatelessWidget {
  const _VolumeChip({required this.volumeCm3});
  final double volumeCm3;

  String _fmt() {
    if (volumeCm3 >= 1000000) {
      return '${(volumeCm3 / 1000000).toStringAsFixed(2)} m³';
    }
    return '${volumeCm3.toStringAsFixed(0)} cm³';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_in_ar, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            'Calculated Volume: ${_fmt()}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
