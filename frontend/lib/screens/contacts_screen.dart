import 'package:flutter/material.dart';
import '../theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _Contact {
  final String name;
  bool sharing;
  _Contact(this.name, this.sharing);
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _contacts = [
    _Contact('Mamá', true),
    _Contact('Ana (roomie)', true),
    _Contact('Luis (hermano)', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de confianza')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.safe,
        onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length,
        itemBuilder: (context, i) {
          final c = _contacts[i];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title:
                  Text(c.name, style: const TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text('Compartir ubicación en tiempo real',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: Switch(
                value: c.sharing,
                activeColor: AppColors.safe,
                onChanged: (v) => setState(() => c.sharing = v),
              ),
            ),
          );
        },
      ),
    );
  }
}
