import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../shared/widgets.dart';
import 'thermal/direct_print.dart';
import '../../shared/theme.dart';

class PdfPreviewState extends Equatable {
  const PdfPreviewState({this.status = LoadStatus.loading, this.bytes, this.fileName = 'document.pdf', this.layout, this.error});
  final LoadStatus status;
  final Uint8List? bytes;
  final String fileName;

  /// The chosen print layout (theme or paper), when the document offers a choice.
  final String? layout;
  final String? error;

  @override
  List<Object?> get props => [status, bytes, fileName, layout, error];
}

/// Loads the data for a document and renders it to PDF, again whenever another layout is chosen.
class PdfPreviewCubit extends Cubit<PdfPreviewState> {
  PdfPreviewCubit(this._build, {String? layout}) : super(PdfPreviewState(layout: layout));

  /// Returns (file name, pdf bytes) for the given layout.
  final Future<(String, Uint8List)> Function(String? layout) _build;

  Future<void> load() async {
    final layout = state.layout;
    emit(PdfPreviewState(layout: layout));
    try {
      final (name, bytes) = await _build(layout);
      // A slower render of a layout the user has since left must not replace the current one.
      if (!isClosed && state.layout == layout) emit(PdfPreviewState(status: LoadStatus.success, bytes: bytes, fileName: name, layout: layout));
    } catch (e) {
      if (!isClosed && state.layout == layout) emit(PdfPreviewState(status: LoadStatus.failure, error: ApiException.from(e).message, layout: layout));
    }
  }

  void layoutChanged(String layout) {
    if (layout == state.layout) return;
    emit(PdfPreviewState(layout: layout));
    load();
  }
}

/// Full-screen PDF preview with print, share and download.
class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.fallbackPath,
    this.buildPdf,
    this.editPath,
    this.layouts = const [],
    this.initialLayout,
    this.buildLayout,
    this.directPrint,
    this.directPrintLayout,
  }) : assert(buildPdf != null || buildLayout != null);

  final String title;

  /// Where Close goes when there is no page to pop back to (e.g. opened by URL).
  final String fallbackPath;
  final String? editPath;

  /// Loads the document's data and returns (file name, pdf bytes).
  final Future<(String, Uint8List)> Function(BuildContext context)? buildPdf;

  /// Print layouts to choose from, as (id, label) — e.g. invoice themes and thermal paper.
  final List<(String, String)> layouts;

  /// The layout shown first; null lets [buildLayout] pick (e.g. the theme saved in settings).
  final String? initialLayout;

  /// Makes the raw ESC/POS bytes for a receipt printer; offered next to the preview when [directPrintLayout] is shown.
  final Future<Uint8List> Function(BuildContext context, PrinterPrefs prefs)? directPrint;
  final String? directPrintLayout;

  /// Like [buildPdf], for documents with [layouts]: renders the chosen layout.
  final Future<(String, Uint8List)> Function(BuildContext context, String? layout)? buildLayout;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => PdfPreviewCubit((layout) => buildLayout != null ? buildLayout!(ctx, layout) : buildPdf!(ctx), layout: initialLayout)..load(),
      child: BlocBuilder<PdfPreviewCubit, PdfPreviewState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => context.canPop() ? context.pop() : context.go(fallbackPath),
            ),
            title: Text(title),
            actions: [
              if (directPrint != null && state.layout == directPrintLayout) DirectPrintButton(makeBytes: (prefs) => directPrint!(context, prefs)),
              if (layouts.isNotEmpty)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: layouts.any((l) => l.$1 == state.layout) ? state.layout : null,
                    hint: const Text('Layout'),
                    icon: const Icon(Icons.style_outlined, size: AppIconSize.md),
                    items: [for (final (id, label) in layouts) DropdownMenuItem(value: id, child: Text(label))],
                    onChanged: (v) => context.read<PdfPreviewCubit>().layoutChanged(v!),
                  ),
                ),
              const SizedBox(width: AppSpace.sm),
              if (editPath != null)
                TextButton.icon(
                  onPressed: () => context.pushReplacement(editPath!),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              const SizedBox(width: AppSpace.sm),
            ],
          ),
          body: switch (state.status) {
            LoadStatus.failure => ErrorRetry(error: state.error ?? 'Could not load', onRetry: context.read<PdfPreviewCubit>().load),
            LoadStatus.success => PdfPreview(
              build: (_) => state.bytes!,
              pdfFileName: state.fileName,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }
}
