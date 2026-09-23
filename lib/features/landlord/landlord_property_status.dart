import '../dashboard/models/property.dart';

bool isOccupied(Property property) => property.isOccupied;

bool isAvailable(Property property) => !property.isOccupied;
