-- Every Supabase project exposes its Postgres schema over a public REST API
-- (PostgREST) by default, reachable with the project's publishable/anon
-- key. This backend never uses that API — it connects to Postgres directly
-- as the table owner, which Row Level Security does not restrict — so
-- enabling RLS here with no policies simply denies the public Data API
-- access to every table (deny-all), with zero effect on this API's own
-- queries.
ALTER TABLE "User" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "RefreshToken" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "OtpCode" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Property" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Booking" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Favorite" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Review" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Thread" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "ThreadParticipant" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Message" ENABLE ROW LEVEL SECURITY;
