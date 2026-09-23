import { Controller, Get } from '@nestjs/common';

/// Render polls this to decide whether a deploy is healthy — see
/// `healthCheckPath` in render.yaml. Deliberately has no dependencies
/// (not even PrismaService), so it stays truthful even if the database is
/// briefly unreachable rather than false-failing the whole deploy.
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok', timestamp: new Date().toISOString() };
  }
}
