import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/claim_notes.dart';
import '../models/models.dart';
import '../theme.dart';

Future<ClaimLink?> showClaimNoteEditor(BuildContext context, {required CaseData caseData,
    ClaimLink? existing, String? claim, String? evidence, Listenable? ownerChanges, bool Function()? ownerCurrent}) =>
  showModalBottomSheet<ClaimLink>(context: context, isScrollControlled: true, useSafeArea: true,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => ClaimNoteEditor(caseData: caseData, existing: existing, initialClaim: claim,
      initialEvidence: evidence, ownerChanges: ownerChanges, ownerCurrent: ownerCurrent));

Future<void> showClaimReading(BuildContext context, ClaimChoice claim) => _read(context,
  claim.suspect.name, '${claim.label}\n\n${claim.text}');
Future<void> showEvidenceReading(BuildContext context, Evidence evidence) => _read(context, evidence.title, evidence.text);
Future<void> _read(BuildContext context, String title, String text) => showModalBottomSheet<void>(
  context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: K.night2,
  builder: (context) => ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
    child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: tDisplay(20)), const SizedBox(height: 10),
      Paper(child: Text(text, style: tBody(15, color: K.ink))), const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
    ]))));

/// A small collapsed extension to the existing evidence notebook, never a required game step.
class ClaimNotesPanel extends StatelessWidget {
  const ClaimNotesPanel({super.key, required this.caseData, required this.links, required this.onAdd,
    required this.onEdit, required this.onRemove});
  final CaseData caseData;
  final List<ClaimLink> links;
  final VoidCallback onAdd;
  final ValueChanged<ClaimLink> onEdit, onRemove;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const PageStorageKey('claim-notes'), tilePadding: EdgeInsets.zero,
    leading: const Icon(Icons.edit_note_rounded, color: K.brass),
    title: Text('یادداشت‌های شخصی (${fa(links.length)})', style: tBody(14, w: FontWeight.w900)),
    subtitle: Text('اختیاری؛ فقط برداشت خودته، نه تأیید بازی', style: tBody(12, color: K.textSoft)),
    children: [
      Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
        onPressed: links.length >= maxClaimLinks ? null : onAdd,
        icon: const Icon(Icons.add_link_rounded), label: const Text('پیوند تازه'))),
      if (links.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12),
        child: Text('می‌تونی یک حرف مظنون رو به مدرکی وصل کنی و بعداً برگردی سراغش.', style: tBody(13, color: K.textSoft))),
      if (links.length >= maxClaimLinks) Text('سقف ${fa(maxClaimLinks)} پیوند این پرونده پر شده؛ یادداشت‌ها قابل ویرایش‌اند.', style: tBody(12, color: K.textSoft)),
      for (final link in links) _card(context, link),
    ],
  );

  Widget _card(BuildContext context, ClaimLink link) {
    final claim = link.resolveClaim(caseData);
    final evidence = caseData.evidenceById(link.evidence);
    return Container(key: ValueKey(link.id), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(12), border: Border.all(color: K.night3)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(link.relation.label, style: tBody(13, color: K.brass, w: FontWeight.w900)),
        TextButton.icon(onPressed: claim == null ? null : () => showClaimReading(context, claim),
          icon: const Icon(Icons.record_voice_over_rounded, size: 18),
          label: Text(claim == null ? 'حرف قبلی مظنون تغییر کرده یا در دسترس نیست' : '${claim.suspect.name} · ${claim.label}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(13))),
        TextButton.icon(onPressed: evidence == null ? null : () => showEvidenceReading(context, evidence),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Text(evidence?.title ?? 'مدرک قبلی در دسترس نیست', style: tBody(13))),
        if (link.evidenceChanged(caseData)) Text('مدرک تغییر کرده؛ پیوند رو دوباره بررسی کن.', style: tBody(12, color: K.textSoft)),
        if (link.note.isNotEmpty) Text(link.note, maxLines: 4, overflow: TextOverflow.ellipsis, style: tBody(14)),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(tooltip: 'ویرایش پیوند', onPressed: () => onEdit(link), icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'حذف پیوند', onPressed: () => onRemove(link), icon: const Icon(Icons.delete_outline_rounded)),
        ]),
      ]));
  }
}

class ClaimNoteEditor extends StatefulWidget {
  const ClaimNoteEditor({super.key, required this.caseData, this.existing, this.initialClaim, this.initialEvidence,
    this.ownerChanges, this.ownerCurrent});
  final CaseData caseData;
  final ClaimLink? existing;
  final String? initialClaim, initialEvidence;
  final Listenable? ownerChanges;
  final bool Function()? ownerCurrent;
  @override
  State<ClaimNoteEditor> createState() => _ClaimNoteEditorState();
}

class _ClaimNoteEditorState extends State<ClaimNoteEditor> {
  late final _choices = claimChoices(widget.caseData);
  String? _claim, _evidence;
  late ClaimRelation _relation = widget.existing?.relation ?? ClaimRelation.checking;
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _ownerChanged = false;
  @override
  void initState() {
    super.initState();
    final claim = widget.existing?.claim ?? widget.initialClaim;
    final evidence = widget.existing?.evidence ?? widget.initialEvidence;
    _claim = _choices.any((c) => c.key == claim) ? claim : null;
    _evidence = widget.caseData.evidence.any((e) => e.id == evidence) ? evidence : null;
    widget.ownerChanges?.addListener(_checkOwner);
    _ownerChanged = !(widget.ownerCurrent?.call() ?? true);
  }
  void _checkOwner() {
    if (mounted && !(widget.ownerCurrent?.call() ?? true)) {
      _note.clear();
      setState(() => _ownerChanged = true);
    }
  }
  @override
  void dispose() {
    widget.ownerChanges?.removeListener(_checkOwner);
    _note.dispose();
    super.dispose();
  }
  InputDecoration _field(String label) => InputDecoration(labelText: label, filled: true, fillColor: K.night,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));

  @override
  Widget build(BuildContext context) {
    if (_ownerChanged) return const SafeArea(child: Padding(padding: EdgeInsets.all(20), child: Text('حساب عوض شده؛ این یادداشت بسته شد.')));
    final selected = _choices.where((c) => c.key == _claim).firstOrNull;
    return ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'پیوند شخصی به مدرک' : 'ویرایش پیوند شخصی', style: tDisplay(20)),
          const SizedBox(height: 6),
          Text('این فقط فرضیهٔ خودته؛ بازی درستی یا نادرستی‌اش رو تأیید نمی‌کنه.', style: tBody(12.5, color: K.textSoft)),
          if (widget.existing != null && (_claim == null || widget.existing!.evidenceChanged(widget.caseData)))
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('بخشی از پرونده تغییر کرده؛ مرجع‌ها رو دوباره انتخاب و بررسی کن.', style: tBody(13, color: K.brass))),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(key: const ValueKey('note-claim'), initialValue: _claim, isExpanded: true,
            decoration: _field('حرف مظنون'), dropdownColor: K.night2,
            items: [for (final c in _choices) DropdownMenuItem(value: c.key,
              child: Text('${c.suspect.name} · ${c.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13)))],
            onChanged: (v) => setState(() => _claim = v)),
          if (selected != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
            child: Paper(child: Text('${selected.label}\n${selected.text}', style: tBody(14, color: K.ink)))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(key: const ValueKey('note-evidence'), initialValue: _evidence, isExpanded: true,
            decoration: _field('مدرک'), dropdownColor: K.night2,
            items: [for (final e in widget.caseData.evidence) DropdownMenuItem(value: e.id,
              child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13)))],
            onChanged: (v) => setState(() => _evidence = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<ClaimRelation>(key: const ValueKey('note-relation'), initialValue: _relation, isExpanded: true,
            decoration: _field('برداشت من'), dropdownColor: K.night2,
            items: [for (final r in ClaimRelation.values) DropdownMenuItem(value: r, child: Text(r.label, style: tBody(13)))],
            onChanged: (v) => setState(() => _relation = v ?? ClaimRelation.checking)),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('note-text'), controller: _note, minLines: 2, maxLines: 4,
            maxLength: maxClaimNoteLength, inputFormatters: [LengthLimitingTextInputFormatter(maxClaimNoteLength)],
            decoration: _field('یادداشت کوتاه (اختیاری)')),
          const SizedBox(height: 12),
          StampButton(label: 'ذخیره‌ی یادداشت', icon: Icons.bookmark_add_outlined,
            onTap: _claim == null || _evidence == null ? null : () {
              if (!(widget.ownerCurrent?.call() ?? true)) { _checkOwner(); return; }
              final e = widget.caseData.evidenceById(_evidence!)!;
              Navigator.pop(context, ClaimLink(claim: _claim!, evidence: e.id, revision: evidenceRevision(e),
                relation: _relation, note: _note.text.trim()));
            }),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        ])));
  }
}
