import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/status.dart';
import '../core/submit_cubit.dart';
import 'widgets.dart';
import 'theme.dart';

/// Dialog with one form whose submission is tracked by a [SubmitCubit]; pops with the result on success.
Future<T?> showSubmitDialog<T>(
  BuildContext context, {
  required String title,
  required List<Widget> Function(VoidCallback submit) fields,
  required Future<T> Function() action,
}) {
  final formKey = GlobalKey<FormState>();
  return showDialog<T>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => SubmitCubit<T>(),
      child: BlocConsumer<SubmitCubit<T>, SubmitState<T>>(
        listener: (ctx, s) {
          if (s.status == SubmitStatus.success) Navigator.pop(ctx, s.result);
          if (s.status == SubmitStatus.failure) showError(ctx, s.error!);
        },
        builder: (ctx, s) {
          void submit() {
            if (validateForm(ctx, formKey, report: showError)) ctx.read<SubmitCubit<T>>().run(action);
          }

          return AlertDialog(
            title: Text(title),
            content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
              key: formKey,
              child: SizedBox(width: AppSize.dialogSm, child: Column(mainAxisSize: MainAxisSize.min, children: fields(submit))),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: s.status == SubmitStatus.submitting ? null : submit, child: const Text('Save')),
            ],
          );
        },
      ),
    ),
  );
}
