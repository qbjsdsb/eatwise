import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecognizePage()),
        ),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<double>(
        future: _getTodayCalories(ref),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('今日已摄入', style: Theme.of(context).textTheme.titleMedium),
                Text('${snapshot.data!.toStringAsFixed(0)} kcal',
                    style: Theme.of(context).textTheme.displaySmall),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<double> _getTodayCalories(WidgetRef ref) async {
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return repo.getTotalCaloriesByDate(date);
  }
}
