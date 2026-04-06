Cross-feature implementation rules:

1. Deterministic first
All money math, dates, balances, reminders, due dates, recurrence, progress, and forecasts must be deterministic.

2. AI second
AI is allowed only for:
- merchant cleanup suggestions
- bill/subscription labeling
- narrative explanations
- recommendations
- anomaly summaries
- what-if natural-language explanation
AI must never silently commit financial state changes.

3. GOAT-only surface
All three modules live inside GOAT Mode.
Do not clutter the standard Billy home experience.
Normal Billy stays lightweight.

4. India-first defaults
Default currency INR.
Support UPI AutoPay labeling in recurring bills.
Keep future architecture open for Account Aggregator-based account linking.

5. Production over demo
No fake placeholder numbers.
No hardcoded mock summaries in final UI.
Every empty state must be graceful.

6. Reuse existing Billy architecture
Integrate with:
- profileProvider
- SupabaseService
- documentsProvider
- analytics-insights pattern where useful for AI layer
- existing navigation and theme structure
Do not create a disconnected parallel architecture.

7. Clean migrations
Every new table must have:
- RLS
- indexes
- updated_at triggers if project uses them
- defensive migrations (`if not exists` where sensible)

8. Responsive design
Must work on mobile and web.
GOAT shell should look premium on both.

9. Backfill safely
Historical documents should be used to generate recurrence and sinking-fund suggestions.
Backfill must be idempotent.

10. Deliver full code
Return complete code and migrations, not pseudo-code.