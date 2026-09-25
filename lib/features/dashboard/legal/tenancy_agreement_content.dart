import '../../../api/models/tenancy_agreement.dart';
import '../models/property.dart';

/// One side of the agreement, built from whatever the persisted
/// [TenancyAgreement] actually has on file — a field the backend didn't
/// capture is labelled as on file rather than guessed.
class TenancyParty {
  const TenancyParty({required this.name, required this.address, required this.phone, required this.email});

  final String name;
  final String address;
  final String phone;
  final String email;
}

class TenancyClause {
  const TenancyClause(this.number, this.title, this.body);

  final int number;
  final String title;
  final String body;
}

/// The filled Memorandum of Understanding for one successful (non-shortlet)
/// rental — the same content feeds both the on-screen viewer and the PDF
/// export, so the two can never drift out of sync.
class TenancyAgreementContent {
  const TenancyAgreementContent({
    required this.propertyTitle,
    required this.madeOnLine,
    required this.landlord,
    required this.tenant,
    required this.clauses,
    required this.generatedNote,
    required this.disclaimer,
  });

  final String propertyTitle;
  final String madeOnLine;
  final TenancyParty landlord;
  final TenancyParty tenant;
  final List<TenancyClause> clauses;
  final String generatedNote;
  final String disclaimer;

  static const documentTitle = 'Memorandum of Understanding';
  static const documentSubtitle = 'Relating to the Letting and Occupation of Residential Premises';
}

const _onFile = 'On file with Home Servant';

String _formatLongDate(DateTime date) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Builds the filled MOU from the real, persisted [agreement] — generated
/// server-side on move-in (see `GET /bookings/:id/tenancy-agreement`).
/// Nothing here is fabricated: lease dates, rent, and both parties' details
/// all come straight from that record.
TenancyAgreementContent buildTenancyAgreementContent(TenancyAgreement agreement) {
  final landlord = TenancyParty(
    name: agreement.landlordName,
    address: _onFile,
    phone: agreement.landlordPhone ?? _onFile,
    email: agreement.landlordEmail ?? _onFile,
  );
  final tenant = TenancyParty(
    name: agreement.tenantName,
    address: _onFile,
    phone: agreement.tenantPhone ?? _onFile,
    email: agreement.tenantEmail ?? _onFile,
  );

  final payFrequency = agreement.priceUnit.toLowerCase() == 'year' ? 'annually' : 'per ${agreement.priceUnit.toLowerCase()}';

  final clauses = [
    TenancyClause(
      1,
      'PROPERTY',
      'The Landlord agrees to let and the Tenant agrees to occupy the property at ${agreement.propertyLocation}, '
          '${agreement.propertyState}, known as "${agreement.propertyTitle}", together with the fixtures and '
          'facilities stated in the attached schedule, if any.',
    ),
    TenancyClause(
      2,
      'TERM AND POSSESSION',
      'The occupation shall commence on ${_formatLongDate(agreement.leaseStartDate)} and end on '
          '${_formatLongDate(agreement.leaseEndDate)}. The Landlord shall give possession to the Tenant on '
          '${_formatLongDate(agreement.leaseStartDate)}. Any renewal shall be by mutual written agreement.',
    ),
    TenancyClause(
      3,
      'RENT',
      'The agreed rent is ₦${formatNaira(agreement.rentAmount)} for the period stated above, payable $payFrequency '
          'on or before the commencement date shown above, via the payment method used at booking on the '
          'Home Servant platform.',
    ),
    const TenancyClause(
      4,
      'RENT INCREASE',
      'Any proposed increase in rent shall be communicated to the Tenant at least twelve (12) months before '
          'the proposed increase, unless a different period is required by applicable law.',
    ),
    const TenancyClause(
      5,
      'SERVICE CHARGES / DEPOSIT',
      'Service charge: Nil, unless otherwise agreed directly between the parties. Security/caution deposit: '
          'Nil, unless otherwise agreed directly between the parties. No undisclosed charge shall be imposed '
          'except as permitted by law.',
    ),
    const TenancyClause(
      6,
      'USE OF PROPERTY',
      'The property shall be used for residential purposes only. The Tenant shall not use it for any '
          'unlawful purpose or cause nuisance or substantial damage.',
    ),
    const TenancyClause(
      7,
      'REPAIRS',
      "The Landlord shall be responsible for major structural repairs, including the roof, foundation, "
          "structural walls and pillars, except where damage is caused by the Tenant. The Tenant shall be "
          "responsible for ordinary internal/minor repairs arising from the Tenant's use, including minor "
          'fittings, locks, sinks, toilet fittings and cupboards, subject to applicable law.',
    ),
    const TenancyClause(
      8,
      'SUBLETTING',
      "The Tenant may sublet the property only with the Landlord's prior written consent, subject to "
          'applicable law.',
    ),
    const TenancyClause(
      9,
      'NOTICE AND TERMINATION',
      'The agreed contractual notice period is one (1) month. This clause is subject to any mandatory '
          'statutory notice period or other requirement applicable to the property. No party shall unlawfully '
          'recover possession or terminate the occupation.',
    ),
    const TenancyClause(
      10,
      'BREACH AND REMEDIES',
      'Where either party materially breaches this MOU, the affected party may require the breach to be '
          'remedied and may seek any lawful remedy, including damages, specific performance, injunction or '
          'recovery of possession where legally available.',
    ),
    const TenancyClause(
      11,
      'PEACEFUL OCCUPATION',
      'The Landlord shall allow the Tenant peaceful occupation of the property during the agreed term, '
          'subject to the Tenant complying with this MOU and applicable law.',
    ),
    const TenancyClause(
      12,
      'AGREEMENT',
      'The Parties confirm that they have read, understood and voluntarily accepted the terms of this MOU. '
          'The terms shall bind the Parties to the extent permitted by applicable law. Where mandatory law '
          'requires a formal tenancy instrument, notice, registration, stamping or other procedure, the '
          'Parties shall comply with it.',
    ),
  ];

  return TenancyAgreementContent(
    propertyTitle: agreement.propertyTitle,
    madeOnLine: 'This Memorandum of Understanding ("MOU") is made on ${_formatLongDate(agreement.leaseStartDate)} between:',
    landlord: landlord,
    tenant: tenant,
    clauses: clauses,
    generatedNote:
        'Generated automatically by Home Servant on ${_formatLongDate(agreement.generatedAt)} for the tenancy '
        'created between the parties above.',
    disclaimer:
        'This is a general-purpose template intended as a starting reference and does not constitute legal '
        'advice. Please have it reviewed by a qualified lawyer and ensure compliance with applicable tenancy '
        'laws before relying on it.',
  );
}
