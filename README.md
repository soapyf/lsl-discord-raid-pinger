# lsl-discord-raid-pinger

A Linden Scripting Language (LSL) script for Second Life combat communities that lets you turn any object into an interactive raid alert button. When clicked, it sends a Discord webhook notification containing the clicker's name, active group, and raider count—and keeps the alert updated live as the fight unfolds.

## Features
- **Instant Raid Alerts:** Clickable object configuration that posts initial raid details (clicker name, group, and raider count) to a Discord webhook.
- **Live Status Updates:** Uses Discord's `?wait=true` query parameter on the initial webhook post to capture the returned message ID, then periodically updates the message via `POST` (or webhook edit requests) on a timer with live attacker vs. defender counts.
- **Built for SL Combat:** Tailored for Second Life roleplay and combat groups needing fast, reliable out-of-world pings.
