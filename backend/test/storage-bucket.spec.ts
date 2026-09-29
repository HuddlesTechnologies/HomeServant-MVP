import { publicBucketRefuses } from '../src/storage/storage.service';

describe('public bucket file types', () => {
  it('accepts everything when Allowed MIME types is not set', () => {
    expect(publicBucketRefuses(null)).toEqual([]);
    expect(publicBucketRefuses([])).toEqual([]);
  });

  it('understands wildcards', () => {
    expect(publicBucketRefuses(['image/*', 'video/*'])).toEqual([]);
  });

  it('lists the types an images-only bucket would refuse', () => {
    expect(publicBucketRefuses(['image/*'])).toEqual(['video/mp4', 'video/quicktime', 'video/x-m4v', 'video/webm']);
    expect(publicBucketRefuses(['image/jpeg', 'image/png', 'video/mp4'])).toEqual([
      'image/webp',
      'image/gif',
      'image/heic',
      'image/heif',
      'video/quicktime',
      'video/x-m4v',
      'video/webm',
    ]);
  });
});
