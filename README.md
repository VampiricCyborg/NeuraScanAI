# 🧠 NeuraScan AI

### Intelligent Behavioural Screening for Neurological Risk Analysis

NeuraScan AI is an AI-assisted behavioural screening platform designed to identify **potential neurological risk indicators** through structured behavioural assessments, cognitive tasks, and interaction analysis.

The system focuses on **early risk screening rather than medical diagnosis**, providing users and healthcare professionals with interpretable behavioural insights that can support further clinical evaluation.

> ⚠️ **Medical Disclaimer:** NeuraScan AI is a screening and research prototype. It does not diagnose neurological disorders, replace a medical professional, or provide medical advice.

---

## 📌 Problem Statement

Neurological disorders can develop gradually, with early behavioural and cognitive changes often being subtle and difficult to identify without structured assessment.

Traditional neurological screening can be:

* Time-consuming
* Dependent on clinical availability
* Difficult to perform frequently
* Subjective for certain behavioural observations
* Limited in its ability to continuously track changes

NeuraScan AI explores how **AI-assisted behavioural analysis** can make preliminary neurological risk screening more accessible, structured, and data-driven.

---

## 💡 Our Approach

NeuraScan AI converts behavioural interactions into measurable indicators across multiple dimensions.

The platform follows a pipeline:

```text
                 ┌─────────────────────┐
                 │       User          │
                 └──────────┬──────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Behavioural Screening │
                │       Interface       │
                └───────────┬───────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        Cognitive       Behavioural    Interaction
          Tasks            Tasks          Signals
              │             │             │
              └─────────────┼─────────────┘
                            ▼
                ┌───────────────────────┐
                │ Feature Extraction &  │
                │ Behavioural Analysis  │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │    Risk Assessment    │
                │       Engine          │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Explainable Screening │
                │       Report          │
                └───────────────────────┘
```

The objective is not to output a simple **"healthy/unhealthy"** classification.

Instead, NeuraScan AI aims to identify **behavioural patterns and risk indicators**, allowing the result to be interpreted in context.

---

# ✨ Key Features

## 🧩 1. Behavioural Screening

The platform collects structured behavioural information through interactive screening activities.

Potential signals include:

* Response time
* Task accuracy
* Interaction consistency
* Recall performance
* Attention patterns
* Motor interaction patterns
* Behavioural deviations
* Task completion behaviour

---

## 🧠 2. Cognitive Assessment

Interactive cognitive tasks can be used to evaluate dimensions such as:

* Memory
* Attention
* Reaction time
* Pattern recognition
* Executive function
* Processing speed

Instead of relying only on questionnaire answers, the platform can analyse **how the user performs a task**.

---

## 📊 3. Multi-Dimensional Risk Analysis

The screening result can be divided into multiple behavioural dimensions rather than relying on a single score.

Example:

```text
Cognitive Performance
████████████████░░░░  78%

Attention
██████████████░░░░░░  70%

Memory
█████████████████░░░  84%

Reaction Time
████████████░░░░░░░░  62%

Behavioural Consistency
███████████████░░░░░  74%
```

This provides a more interpretable representation of the user's performance.

---

## 🔍 4. Explainable Results

A major objective of NeuraScan AI is to avoid a black-box result such as:

> **"Risk Score: 73%"**

Instead, the system should explain which behavioural dimensions contributed to the screening outcome.

For example:

```text
Overall Screening
        ↓
Moderate Risk Indicators
        ↓
 ┌────────────────────────────┐
 │ Attention       → Elevated │
 │ Memory          → Normal   │
 │ Reaction Time   → Elevated │
 │ Consistency     → Normal   │
 └────────────────────────────┘
```

This makes the result easier to understand and potentially more useful for subsequent clinical evaluation.

---

## 📈 5. Progress Tracking

Repeated screenings can enable longitudinal analysis.

Instead of analysing one isolated session:

```text
Session 1 ──► Session 2 ──► Session 3 ──► Session 4
    │             │             │             │
    ▼             ▼             ▼             ▼
  Score         Score         Score         Score
```

The system can identify changes in behavioural performance over time.

This is particularly valuable because **trends may provide more information than a single screening session**.

---

# 🖥️ Prototype

The current prototype is a **mobile-first Flutter application** demonstrating the core user experience and screening workflow across a complete multi-screen journey.

### Current Prototype Stack

| Layer           | Technology                        |
| --------------- | --------------------------------- |
| Framework       | Flutter (Dart)                    |
| UI              | Material 3 — custom mobile design |
| State           | Flutter StatefulWidget            |
| Data Processing | Dart (in-app logic)               |
| Storage         | In-memory prototype state         |
| Platforms       | Android, iOS, Web, Desktop        |

The prototype does **not** require a backend or AI model to demonstrate the complete user journey.

### Screens Implemented

| Screen                  | Description                                              |
| ----------------------- | -------------------------------------------------------- |
| Splash Screen           | App entry with branding and disclaimer                   |
| Onboarding              | 3-step walkthrough explaining the screening approach     |
| Dashboard               | Wellness snapshot, domain scores, baseline progress      |
| Assessment List         | Overview of the four assessments with progress tracking  |
| Memory Recall           | Timed word memorisation and recall task                  |
| Reaction Response       | Tap-on-change reaction time task (5 rounds)              |
| Speech Assessment       | Prompted free-speech recording task                      |
| Motor Stability Test    | Spiral-tracing task using touch input and CustomPainter  |
| Behavioural Report      | Explainable result with domain contribution breakdown    |

---

# 🏗️ System Architecture

The long-term architecture is designed to evolve from the current frontend prototype into an AI-powered screening platform.

```text
                         ┌───────────────┐
                         │    Patient    │
                         │     / User    │
                         └───────┬───────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Web / Mobile Client  │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ Screening Engine        │
                    │                        │
                    │ • Cognitive Tasks      │
                    │ • Behavioural Tasks    │
                    │ • Interaction Capture  │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ Feature Extraction      │
                    │                        │
                    │ • Accuracy             │
                    │ • Reaction Time        │
                    │ • Consistency          │
                    │ • Interaction Signals  │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ AI / ML Analysis Layer  │
                    │                        │
                    │ Classification         │
                    │ Anomaly Detection      │
                    │ Pattern Analysis       │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ Explainability Layer    │
                    └────────────┬───────────┘
                                 │
                         ┌───────┴────────┐
                         ▼                ▼
                 ┌──────────────┐ ┌───────────────┐
                 │ User Report  │ │ Clinician View│
                 └──────────────┘ └───────────────┘
```

---

# 🧪 Screening Workflow

A typical screening session follows:

### 1. User Onboarding

The user enters basic information required for the screening session.

### 2. Baseline Assessment

The platform establishes baseline behavioural performance.

### 3. Interactive Tasks

The user completes a series of cognitive and behavioural tasks.

### 4. Signal Collection

The system records relevant measurable signals such as:

* Accuracy
* Completion time
* Reaction time
* Interaction patterns
* Task consistency

### 5. Feature Extraction

Raw interactions are transformed into structured behavioural features.

### 6. Risk Analysis

The analysis engine evaluates behavioural patterns against the screening model.

### 7. Explainable Report

The platform generates a structured report highlighting:

* Overall screening status
* Individual behavioural dimensions
* Potential areas of concern
* Performance trends
* Recommended next step: professional evaluation where appropriate

---

# 🔬 AI/ML Roadmap

The current prototype is primarily frontend-focused. The planned AI architecture can evolve into:

```text
Raw Behavioural Data
        │
        ▼
Data Preprocessing
        │
        ▼
Feature Engineering
        │
        ├───────────────┐
        ▼               ▼
Statistical        ML Models
Analysis
        │               │
        └───────┬───────┘
                ▼
        Risk Estimation
                │
                ▼
       Explainability Layer
                │
                ▼
       Screening Report
```

Potential techniques include:

* Classical machine learning
* Time-series analysis
* Anomaly detection
* Classification models
* Behavioural clustering
* Ensemble models
* Explainable AI techniques

Model selection should ultimately be driven by **clinical validity, dataset quality, interpretability, and validation performance**, rather than novelty alone.

---

# 🛡️ Privacy & Responsible AI

Because NeuraScan AI deals with potentially sensitive behavioural information, privacy and responsible AI are core design requirements.

### Principles

* Collect only necessary information
* Avoid unnecessary personally identifiable information
* Encrypt sensitive data in production
* Use secure authentication and authorization
* Maintain audit logs
* Provide transparent explanations
* Avoid unsupported medical claims
* Clearly communicate uncertainty
* Obtain appropriate user consent
* Follow applicable healthcare and data-protection requirements

### Important Design Principle

NeuraScan AI should **assist screening, not replace clinicians**.

The system should never present a screening result as a confirmed diagnosis.

---

# ⚖️ Ethical Considerations

AI-based neurological screening introduces several important risks.

### False Positives

A user may be incorrectly flagged as having elevated risk.

### False Negatives

A user with genuine symptoms may receive a low-risk screening result.

### Dataset Bias

If training data is not representative, model performance may vary across populations.

### Behavioural Ambiguity

Poor performance can result from many factors unrelated to neurological disease, including:

* Fatigue
* Stress
* Lack of familiarity with technology
* Language
* Environment
* Education
* Temporary illness

Therefore, behavioural signals must always be interpreted within context.

---

# 🚀 Future Scope

The prototype can evolve into a full-scale neurological screening platform.

### Phase 1 — Prototype

* [x] Interactive screening interface
* [x] Behavioural task workflow
* [x] Result visualization
* [x] Responsive mobile-first UI (Flutter)
* [x] Basic risk analysis simulation

### Phase 2 — Intelligent Screening

* [ ] Real behavioural feature extraction
* [ ] ML-based risk modelling
* [ ] Personalized baseline generation
* [ ] Anomaly detection
* [ ] Explainable AI

### Phase 3 — Longitudinal Intelligence

* [ ] User profiles
* [ ] Historical screening data
* [ ] Progress tracking
* [ ] Behavioural trend analysis
* [ ] Automated change detection

### Phase 4 — Clinical Platform

* [ ] Clinician dashboard
* [ ] Secure authentication
* [ ] Role-based access control
* [ ] Secure cloud infrastructure
* [ ] Structured clinical reports
* [ ] Integration with healthcare workflows

### Phase 5 — Research & Validation

* [ ] Curated datasets
* [ ] Clinical collaboration
* [ ] Model validation
* [ ] Bias evaluation
* [ ] Prospective studies
* [ ] Regulatory assessment

---

# 📂 Project Structure

```text
NeuraScan-AI/
│
├── lib/
│   └── main.dart              # All screens and app logic
│
├── pubspec.yaml               # Flutter dependencies
│
└── README.md
```

> The `neurascan/` subdirectory contains a default Flutter scaffold and is not part of the active prototype.

---

# ⚙️ Getting Started

## Prerequisites

* Flutter SDK (>=3.0.0)
* Dart SDK
* Android Studio / Xcode / VS Code with Flutter extension

## Installation

Clone the repository:

```bash
git clone https://github.com/<your-username>/NeuraScan-AI.git
```

Navigate into the project:

```bash
cd NeuraScan-AI
```

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

---

# 🗺️ Production Architecture — Planned

A future production implementation could use:

```text
Frontend
   │
   ▼
API Gateway
   │
   ▼
Backend Services
   │
   ├───────────────┐
   ▼               ▼
Assessment       User/Data
Service          Service
   │               │
   └───────┬───────┘
           ▼
      Feature Store
           │
           ▼
       ML Pipeline
           │
           ▼
     Risk Analysis
           │
           ▼
    Explainability
           │
           ▼
     Report Service
```

Potential technologies for the production version:

* **Frontend:** Flutter / Next.js / React
* **Backend:** FastAPI
* **Database:** PostgreSQL
* **Cache:** Redis
* **ML:** Python / scikit-learn / PyTorch
* **Model Serving:** FastAPI / dedicated inference service
* **Containerization:** Docker
* **Cloud:** AWS
* **Storage:** Amazon S3
* **Monitoring:** Prometheus / Grafana
* **Authentication:** OAuth 2.0 / JWT
* **CI/CD:** GitHub Actions

These technologies are part of the proposed production architecture and are **not required by the current prototype**.

---

# 📊 Example Output

A future screening report may resemble:

```text
╔══════════════════════════════════════╗
║       NEURASCAN AI SCREENING         ║
╠══════════════════════════════════════╣
║                                      ║
║ Overall Screening: MODERATE          ║
║                                      ║
║ Cognitive Performance       78%      ║
║ Attention                   70%      ║
║ Memory                      84%      ║
║ Reaction Time               62%      ║
║ Behavioural Consistency     74%      ║
║                                      ║
╠══════════════════════════════════════╣
║ Key Observations                     ║
║                                      ║
║ • Reduced reaction speed             ║
║ • Attention variability              ║
║ • Memory performance within range    ║
║                                      ║
╠══════════════════════════════════════╣
║ Recommendation                       ║
║                                      ║
║ Consider professional evaluation     ║
║ if concerns persist.                 ║
╚══════════════════════════════════════╝
```

This example is illustrative only and does **not represent a medically validated assessment**.

---

# 🎯 Project Goals

NeuraScan AI aims to demonstrate how modern AI and behavioural computing can contribute to:

* Earlier identification of potential risk indicators
* More accessible preliminary screening
* Objective behavioural measurements
* Longitudinal monitoring
* Explainable AI-assisted analysis
* Data-driven clinical support

The long-term vision is to build a **privacy-first, explainable, clinically responsible AI screening platform** rather than simply another medical chatbot or symptom checker.

---

# 👥 Team

**NeuraScan AI**

Developed as an AI/technology research and prototype project.

---

# 📄 Disclaimer

NeuraScan AI is currently a research/prototype system.

It is **not a medical device**, does not provide medical diagnosis, and should not be used to make medical decisions.

Any real-world deployment would require appropriate:

* Clinical validation
* Dataset validation
* Safety testing
* Privacy review
* Security assessment
* Regulatory compliance
* Professional oversight

---

# ⭐ Vision

> **From behavioural signals to meaningful neurological insights — responsibly.**

NeuraScan AI explores the intersection of **Artificial Intelligence, behavioural computing, human-computer interaction, and healthcare technology** to make neurological risk screening more accessible, interpretable, and data-driven.
