import '../dashboard/models/property.dart';

/// Which of the 8 seed listings are mock-occupied — there's no real
/// tenancy backing this app, so "occupied" is just a fixed subset rather
/// than something computed from actual leases. Any property outside this
/// set (including every property a landlord adds through Add Property)
/// counts as available; see [isOccupied]/[isAvailable].
const occupiedPropertyIds = {
  'house-agege-2br',
  'house-magodo-3br',
  'shortlet-lekki-studio',
  'shortlet-vi-luxury',
};

bool isOccupied(Property property) => occupiedPropertyIds.contains(property.id);

bool isAvailable(Property property) => !isOccupied(property);
