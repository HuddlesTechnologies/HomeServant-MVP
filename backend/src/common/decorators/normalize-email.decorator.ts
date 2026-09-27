import { Transform } from 'class-transformer';

/// Email addresses are compared without regard to case or surrounding
/// spaces: "Ada@Example.com " and "ada@example.com" are one account. Every
/// DTO field carrying an email uses this, so what reaches the services (and
/// the database) is always trimmed and lower-cased.
export function NormalizeEmail(): PropertyDecorator {
  return Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value));
}
