import { IsEnum } from 'class-validator';
import { ReportStatus } from '@prisma/client';

export class SetReportStatusDto {
  @IsEnum(ReportStatus)
  status!: ReportStatus;
}
