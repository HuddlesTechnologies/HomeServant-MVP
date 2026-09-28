import { Logger } from '@nestjs/common';
import { IdCheckStatus } from '@prisma/client';
import { IdCheckProvider, IdCheckRequest, IdCheckResult, idCheckResult } from './id-check-provider.interface';

/// The development default: looks nothing up and says so, which leaves
/// every submission for a moderator — exactly how verification worked
/// before automated checks existed.
///
/// It deliberately does NOT pretend to match (the way ConsoleOtpProvider
/// prints a usable code), because a match is what verifies an account
/// without a human: a staging or production service accidentally left on
/// the default would hand out verified badges to anyone who typed eleven
/// digits. Tests cover the match path with their own fake provider.
export class ConsoleIdCheckProvider implements IdCheckProvider {
  readonly name = 'console';
  private readonly logger = new Logger('IdCheck');

  async check(request: IdCheckRequest): Promise<IdCheckResult> {
    this.logger.log(`No ID check provider configured — leaving this ${request.idType} for manual review`);
    return idCheckResult(this.name, IdCheckStatus.UNSUPPORTED, 'No ID check provider is configured, so this was not checked automatically.');
  }
}
