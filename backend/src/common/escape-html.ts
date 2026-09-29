/// Escapes text for use inside an email's HTML. Every name, title, reason or
/// other user- or admin-typed value put into email HTML must go through
/// this; otherwise, for example, a tenant could name themselves with a link
/// or markup that then renders in their landlord's email.
export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}
