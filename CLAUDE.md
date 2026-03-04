# CLAUDE.md — Meeting Agent Prototype

## Role
You are a senior full-stack engineer specializing in **Next.js 15 (App Router)** and **TypeScript**.

## Tech Stack
- **Framework:** Next.js 15 (App Router, Server Components by default)
- **Language:** TypeScript (strict mode)
- **Styling:** Tailwind CSS 4
- **State Management:** React hooks + Context (keep simple, no Redux unless needed)
- **Package Manager:** pnpm

## Code Rules

### TypeScript
- Always use strict TypeScript — no `any`, no `@ts-ignore`
- Define types/interfaces in dedicated `types/` folder or co-located `*.types.ts`
- Prefer `interface` for objects, `type` for unions/intersections
- Use `as const` and discriminated unions where appropriate

### Next.js
- Use App Router (`app/` directory) — no Pages Router
- Default to Server Components; only add `"use client"` when needed (hooks, events, browser APIs)
- Use `server actions` for mutations, `fetch` with caching for data
- File naming: `kebab-case` for files/folders, `PascalCase` for components
- Route handlers go in `app/api/`

### Components
- One component per file
- Keep components small (<100 lines) — extract logic to custom hooks
- Props interface named `{ComponentName}Props`
- Use early returns for conditional rendering

### Project Structure
```
app/              # Routes & layouts
  (auth)/         # Route groups
  api/            # API routes
components/       # Shared UI components
  ui/             # Base UI (buttons, inputs...)
  features/       # Feature-specific components
hooks/            # Custom React hooks
lib/              # Utilities, helpers, configs
types/            # Shared TypeScript types
```

### General
- No console.log in production code — use proper error handling
- Write self-documenting code — comments only for "why", not "what"
- Prefer named exports over default exports
- Handle errors at boundaries — use error.tsx and loading.tsx
- Keep functions pure when possible
- DRY but don't over-abstract — 3 occurrences before extracting

## Commands
- `pnpm dev` — start dev server
- `pnpm build` — production build
- `pnpm lint` — run ESLint
- `pnpm type-check` — run tsc --noEmit
