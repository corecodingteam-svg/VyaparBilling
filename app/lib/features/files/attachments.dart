import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../data/repositories/files_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/widgets.dart';

/// A file on a transaction. [attachmentId] is null until the transaction itself has been saved.
class AttachmentDraft extends Equatable {
  const AttachmentDraft({this.attachmentId, required this.fileId, required this.name, required this.mimeType});
  final String? attachmentId;
  final String fileId;
  final String name;
  final String mimeType;

  @override
  List<Object?> get props => [attachmentId, fileId, name, mimeType];
}

class AttachmentsState extends Equatable {
  const AttachmentsState({this.items = const [], this.busy = false, this.error, this.errorRev = 0});
  final List<AttachmentDraft> items;
  final bool busy;
  final String? error;

  /// Bumped with every new error so the same message can be shown twice.
  final int errorRev;

  @override
  List<Object?> get props => [items, busy, error, errorRev];
}

/// Files attached to one invoice, expense or payment. On an existing transaction changes apply
/// straight away; on a new one the uploads wait until [commit] is called with the saved id.
class AttachmentsCubit extends Cubit<AttachmentsState> {
  AttachmentsCubit(this._files, {required this.ownerType, this.ownerId}) : super(const AttachmentsState());

  final FilesRepository _files;

  /// invoice | expense | payment
  final String ownerType;
  final String? ownerId;

  void _fail(Object e) => emit(AttachmentsState(items: state.items, error: ApiException.from(e).message, errorRev: state.errorRev + 1));

  Future<void> load() async {
    if (ownerId == null) return;
    try {
      final list = await _files.attachments(ownerType, ownerId!);
      emit(AttachmentsState(items: [for (final a in list) AttachmentDraft(attachmentId: a.id, fileId: a.fileId, name: a.name, mimeType: a.mimeType)]));
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> add({required String name, required String mimeType, required Uint8List bytes}) async {
    if (state.busy) return;
    emit(AttachmentsState(items: state.items, busy: true, errorRev: state.errorRev));
    try {
      final file = await _files.upload(name: name, mimeType: mimeType, bytes: bytes);
      if (ownerId == null) {
        emit(AttachmentsState(items: [...state.items, AttachmentDraft(fileId: file.id, name: file.name, mimeType: file.mimeType)], errorRev: state.errorRev));
      } else {
        await _files.attach(ownerType, ownerId!, file.id);
        await load();
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> remove(AttachmentDraft a) async {
    try {
      if (a.attachmentId != null) await _files.detach(a.attachmentId!);
      emit(AttachmentsState(items: state.items.where((x) => x != a).toList(), errorRev: state.errorRev));
    } catch (e) {
      _fail(e);
    }
  }

  /// Attaches the files added before the transaction existed, then starts empty for the next one.
  Future<void> commit(String savedOwnerId) async {
    final pending = state.items.where((a) => a.attachmentId == null).toList();
    try {
      for (final a in pending) {
        await _files.attach(ownerType, savedOwnerId, a.fileId);
      }
      if (ownerId == null) emit(AttachmentsState(errorRev: state.errorRev));
    } catch (e) {
      _fail(e);
    }
  }

  Future<Uint8List?> bytes(AttachmentDraft a) => _files.bytesOrNull(a.fileId);
}

/// "Attach bill / photo" row for a form. Expects an [AttachmentsCubit] above it.
class AttachmentsField extends StatelessWidget {
  const AttachmentsField({super.key, this.label = 'Attachments'});
  final String label;

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<AttachmentsCubit>();
    try {
      final file = await pickUpload(allowPdf: true);
      if (file != null) await cubit.add(name: file.name, mimeType: file.mimeType, bytes: file.bytes);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _open(BuildContext context, AttachmentDraft a) async {
    final cubit = context.read<AttachmentsCubit>();
    final bytes = await cubit.bytes(a);
    if (!context.mounted) return;
    if (bytes == null) return showError(context, ApiException('Could not open the file.'));
    if (!a.mimeType.startsWith('image/')) {
      await saveBytesFile(a.name, bytes, mimeType: a.mimeType);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.name, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520), child: InteractiveViewer(child: Image.memory(bytes))),
        actions: [
          TextButton(onPressed: () => saveBytesFile(a.name, bytes, mimeType: a.mimeType), child: const Text('Download')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AttachmentsCubit, AttachmentsState>(
      listenWhen: (a, b) => a.errorRev != b.errorRev,
      listener: (context, s) => showError(context, ApiException(s.error ?? 'Could not attach the file.')),
      builder: (context, s) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in s.items)
            InputChip(
              avatar: Icon(a.mimeType.startsWith('image/') ? Icons.image_outlined : Icons.picture_as_pdf_outlined, size: 18),
              label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(a.name, overflow: TextOverflow.ellipsis)),
              onPressed: () => _open(context, a),
              onDeleted: () => context.read<AttachmentsCubit>().remove(a),
              deleteButtonTooltipMessage: 'Remove',
            ),
          OutlinedButton.icon(
            onPressed: s.busy ? null : () => _pick(context),
            icon: s.busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file, size: 18),
            label: Text(s.items.isEmpty ? label : 'Add another'),
          ),
        ],
      ),
    );
  }
}

/// Loads one stored image's bytes (null while loading or when there is none).
class StoredImageCubit extends Cubit<Uint8List?> {
  StoredImageCubit(FilesRepository files, String? fileId) : super(null) {
    files.bytesOrNull(fileId).then((b) {
      if (!isClosed) emit(b);
    });
  }
}

/// Shows an uploaded image by file id, with [placeholder] while it loads or when it is missing.
class StoredImage extends StatelessWidget {
  const StoredImage({super.key, required this.fileId, required this.placeholder, this.fit = BoxFit.contain});
  final String? fileId;
  final Widget placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (fileId == null) return placeholder;
    return BlocProvider(
      key: ValueKey(fileId),
      create: (ctx) => StoredImageCubit(ctx.read(), fileId),
      child: BlocBuilder<StoredImageCubit, Uint8List?>(builder: (_, bytes) => bytes == null ? placeholder : Image.memory(bytes, fit: fit)),
    );
  }
}

/// A picture slot with Upload / Remove, used for the logo, the signature and item images.
/// It uploads the chosen image itself and reports the new file id (null = removed).
class ImageSlot extends StatelessWidget {
  const ImageSlot({super.key, required this.label, required this.fileId, required this.onChanged, this.width = 150, this.height = 100, this.icon = Icons.image_outlined});
  final String label;
  final String? fileId;
  final ValueChanged<String?> onChanged;
  final double width;
  final double height;
  final IconData icon;

  Future<void> _pick(BuildContext context) async {
    final files = context.read<FilesRepository>();
    try {
      final picked = await pickUpload();
      if (picked == null) return;
      final file = await files.upload(name: picked.name, mimeType: picked.mimeType, bytes: picked.bytes);
      onChanged(file.id);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _pick(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: StoredImage(
              fileId: fileId,
              placeholder: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: muted),
                  const SizedBox(height: 4),
                  Text(fileId == null ? 'Upload' : 'Loading…', style: TextStyle(fontSize: 12, color: muted)),
                ]),
              ),
            ),
          ),
        ),
        if (fileId != null)
          TextButton(
            onPressed: () => onChanged(null),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Remove'),
          ),
      ],
    );
  }
}
