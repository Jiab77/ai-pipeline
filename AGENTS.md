# AGENTS.md

This file describes the work methodology and high-level design principles used in this project.

## Keep the human in the loop

One of the major mistakes of the AI industry is believing that removing the human from the loop is a good idea.

Human judgment remains the final authority and an essential safeguard when working with AI models. Humans can make mistakes, and so can AI models.

Cross-checks and reviews help discover and fix issues that either side might miss on its own.

## Framework

The behavioral rules used in this project come from a modified version of the [AI-Framework](https://github.com/jiab77/ai-framework) project.

These rules are stored in `data/framework` and loaded by the pipeline.

> The exact rules and files may be shared publicly at some point.

## Architecture at a glance

Jarvis is an AI collaborator integrated into a Bash-first pipeline. The model can request actions, but the local pipeline remains responsible for validating and executing them.

A simplified request flow looks like this:

```text
Human request
→ CLI / Web entry point
→ Core orchestration and session state
→ Active provider and model
→ Optional tool call validated and dispatched by tools.sh
→ Tool result returned to the model
→ Response and human review
```

The main responsibilities are intentionally separated:

* `cli.sh`: interactive command-line entry point and human-facing commands
* `core.sh`: orchestration, provider integration, session state, and inference/tool loops
* `config/`: runtime configuration, provider definitions and capabilities, and current session state
* `tools.sh`: model-facing tool handlers and local dispatch
* `tools/tools*.json`: contracts describing the tools exposed to the model
* `engines/`: native image, video, and voice engines
* `lib/`: reusable source-only Bash primitives
* `plugins/`: optional capabilities
* `data/memory/`: persistent project context, read from disk when needed

The source code remains the source of truth for implemented behavior. Documentation must follow the code, and planned capabilities must be identified as such.

## Models used during development

The models used to build this project vary depending on my needs and available resources.

The following list is a non-exhaustive historical snapshot, not a runtime support matrix or a list of requirements:

* `gemini-3.5-flash`
* `deepseek-4.1-pro` / `deepseek-flash`
* `glm-5.3` / `glm-5.3-flash` / `glm-5.3-flashx`
* `kimi-k3` / `kimi-k3.1-pro` / `kimi-k3.1-pro-highspeed`
* `gpt-6-astra`, `gemini-3-8-flash`

Several free models provided by [OpenRouter](https://openrouter.ai) have also been used.

The runtime availability of providers and models is a separate concern; refer to the current code and release documentation for the implemented behavior.

## Skills

Human-curated skills stored in `data/skills/` provide models with reusable technical knowledge, coding conventions, and working methods derived from human experience.

They help maintain consistent practices across models and support the collaboration without replacing human judgment and review.

## Code Reviews

The code review cycle is pretty simple:

1. All AI-written code is reviewed by the human
2. All human-written code is reviewed by the AI
3. Relevant changes are checked with appropriate static analysis and tests, including failure paths when applicable

Nothing is released until mutual reviews and the relevant verification steps are complete.

## Collaboration

This document is itself an example of the collaboration between the human (Jiab77) and the AI (Jarvis).

The human wrote the initial version, which was then reviewed by the AI. The AI was also asked to produce its own version for comparison and idea exchange.

The final version combines both drafts and was validated by the human.
