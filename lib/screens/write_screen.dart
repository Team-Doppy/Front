import 'package:flutter/material.dart';

class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key});

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('글쓰기')));
  }
}
