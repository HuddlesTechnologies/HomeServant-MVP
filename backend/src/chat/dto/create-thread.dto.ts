import { IsOptional, IsUUID } from 'class-validator';

export class CreateThreadDto {
  @IsUUID()
  recipientId!: string;

  /// The property this thread is about, if opened from a property detail
  /// screen ("Message Landlord") — kept optional so a general conversation
  /// (not tied to a specific listing) is still possible.
  @IsOptional()
  @IsUUID()
  propertyId?: string;
}
