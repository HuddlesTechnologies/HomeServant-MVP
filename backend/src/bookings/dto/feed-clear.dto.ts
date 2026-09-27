import { ArrayMaxSize, IsArray, IsBoolean, IsOptional, IsUUID } from 'class-validator';

export class FeedClearDto {
  @IsBoolean()
  cleared!: boolean;

  /// Omit to clear every current pending request ("Clear all").
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsUUID('4', { each: true })
  bookingIds?: string[];
}
