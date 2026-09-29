import { PartialType } from '@nestjs/mapped-types';
import { IsBoolean, IsOptional } from 'class-validator';
import { CreatePropertyDto } from './create-property.dto';

export class UpdatePropertyDto extends PartialType(CreatePropertyDto) {
  @IsOptional()
  @IsBoolean()
  isOccupied?: boolean;

  /// The landlord hiding (true) or showing again (false) this listing —
  /// only an unoccupied listing can be hidden. See Property.hiddenByLandlordAt.
  @IsOptional()
  @IsBoolean()
  isHidden?: boolean;
}
