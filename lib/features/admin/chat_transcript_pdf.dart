import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/date_format.dart';
import '../dashboard/chat_thread_screen.dart' show ChatMessage;

/// Renders a chat transcript as a downloadable PDF, for an admin who wants
/// a local backup/record of a conversation with a user — mirrors the exact
/// pattern `tenancy_agreement_pdf.dart` already uses (a `pw.Document` built
/// with `pw.MultiPage`, Noto Sans for glyphs the core PDF fonts lack).
Future<pw.Document> buildChatTranscriptPdf({
  required String contactName,
  required List<ChatMessage> messages,
}) async {
  final navy = PdfColor.fromInt(0xFF10233F);
  final baseFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Chat Transcript', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: navy)),
                pw.SizedBox(height: 4),
                pw.Text('Conversation with $contactName', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                pw.Text(
                  'Exported ${formatShortDate(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 14),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 8),
              ],
            )
          : pw.SizedBox(),
      build: (context) => [
        for (final message in messages)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  message.fromMe ? 'Admin' : contactName,
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: navy),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  message.attachmentUrl != null && message.text.isEmpty ? '[Photo]' : message.text,
                  style: const pw.TextStyle(fontSize: 10.5),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  return doc;
}
