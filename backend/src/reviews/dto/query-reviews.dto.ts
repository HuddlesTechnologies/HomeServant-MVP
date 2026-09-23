import { IsUUID } from 'class-validator';

export class QueryReviewsDto {
  @IsUUID()
  propertyId!: string;
}
