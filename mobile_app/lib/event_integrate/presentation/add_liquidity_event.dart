import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/liquidity_event.dart';

class AddLiquidityEventScreen extends StatefulWidget {
  const AddLiquidityEventScreen({super.key});

  @override
  State<AddLiquidityEventScreen> createState() => _AddLiquidityEventScreenState();
}

class _AddLiquidityEventScreenState extends State<AddLiquidityEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _type = 'fixed_deposit';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 90));

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final event = LiquidityEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text,
      amount: double.parse(_amountController.text),
      maturityDate: _selectedDate,
      type: _type,
    );

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('liquidity_events')
        .doc(event.id)
        .set(event.toJson());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liquidity event added!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Liquidity Event')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title (e.g., Maybank FD)'),
                validator: (v) => v!.isEmpty ? 'Enter title' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (\$)'),
                validator: (v) => v!.isEmpty ? 'Enter amount' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(value: 'fixed_deposit', child: Text('Fixed Deposit')),
                  DropdownMenuItem(value: 'bond', child: Text('Bond')),
                ],
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 10),
              ListTile(
                title: Text('Maturity Date: ${_selectedDate.toLocal()}'.split(' ')[0]),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveEvent,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text('ADD EVENT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}