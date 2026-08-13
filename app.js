const STORAGE_KEY = 'neurascan-ai-demo';

const defaultData = {
  user: {
    name: 'Avery Chen',
    role: 'Research Participant',
    age: '32'
  },
  baseline: {
    sessions: 12,
    confidence: 82,
    stability: 88
  },
  assessmentSessions: [
    { timestamp: '2026-06-11', memoryScore: 92, reactionTime: 272, speechScore: 89, motorScore: 90, interactionScore: 86, overallStability: 91, baselineDeviation: 2 },
    { timestamp: '2026-06-14', memoryScore: 90, reactionTime: 280, speechScore: 88, motorScore: 89, interactionScore: 85, overallStability: 89, baselineDeviation: 3 },
    { timestamp: '2026-06-17', memoryScore: 91, reactionTime: 276, speechScore: 90, motorScore: 88, interactionScore: 84, overallStability: 88, baselineDeviation: 2 },
    { timestamp: '2026-06-20', memoryScore: 88, reactionTime: 285, speechScore: 87, motorScore: 87, interactionScore: 83, overallStability: 87, baselineDeviation: 4 },
    { timestamp: '2026-06-23', memoryScore: 90, reactionTime: 278, speechScore: 89, motorScore: 89, interactionScore: 84, overallStability: 87, baselineDeviation: 3 }
  ],
  cognitiveMetrics: { current: 92, trend: [89, 90, 91, 88, 90] },
  speechMetrics: { current: 88, trend: [86, 87, 88, 85, 88] },
  motorMetrics: { current: 91, trend: [90, 89, 88, 87, 89] },
  interactionMetrics: { current: 86, trend: [83, 84, 85, 82, 84] },
  riskHistory: []
};

const app = document.getElementById('app');
const state = {
  screen: 'splash',
  onboardingStep: 0,
  navigation: 'home',
  demoScenario: 'stable',
  memoryInput: '',
  memoryVisible: true,
  memoryCountdown: 10,
  memoryTimerId: null,
  memoryStarted: false,
  reactionResults: [],
  reactionRound: 0,
  reactionReady: false,
  reactionStartedAt: 0,
  reactionInitialized: false,
  speechRecorded: false,
  motorPath: [],
  motorMetrics: null,
  assessmentProgress: 0,
  completedAssessments: [],
  analysisStep: 0,
  result: null,
  trendTab: 'overall',
  privacy: {
    microphone: true,
    motion: true,
    analytics: true
  },
  data: loadData()
};

function loadData() {
  const stored = localStorage.getItem(STORAGE_KEY);
  return stored ? JSON.parse(stored) : defaultData;
}

function saveData() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state.data));
}

function setScreen(screen) {
  if (state.memoryTimerId && screen !== 'memory') {
    clearInterval(state.memoryTimerId);
    state.memoryTimerId = null;
  }
  state.screen = screen;
  if (screen === 'home') {
    state.navigation = 'home';
  }
  render();
}

function setNavigation(tab) {
  state.navigation = tab;
  if (tab === 'home') setScreen('home');
  if (tab === 'assess') setScreen('quickScan');
  if (tab === 'insights') setScreen('trends');
  if (tab === 'profile') setScreen('privacy');
}

function cycleDemoScenario() {
  const scenarios = ['stable', 'change', 'significant'];
  const currentIndex = scenarios.indexOf(state.demoScenario);
  state.demoScenario = scenarios[(currentIndex + 1) % scenarios.length];
  render();
}

function getScenarioResult() {
  if (state.demoScenario === 'change') {
    return {
      status: 'BEHAVIORAL CHANGE DETECTED',
      subtitle: 'Multiple behavioral domains have changed compared with your established baseline.',
      badgeClass: 'status-change',
      overall: 71,
      cognitive: 76,
      speech: 73,
      motor: 81,
      interaction: 78,
      explanation: 'Memory and motor performance moved away from your baseline while speech timing and interaction consistency showed a moderate shift.',
      contribution: { cognitive: 35, speech: 25, motor: 25, interaction: 15 },
      deviations: { cognitive: -14, speech: -11, motor: -8, interaction: -4 },
      recommendation: 'Repeated changes across multiple assessments may warrant further evaluation.'
    };
  }
  if (state.demoScenario === 'significant') {
    return {
      status: 'MULTIDOMAIN DEVIATION',
      subtitle: 'The current assessment pattern suggests meaningful behavioral deviation across several domains.',
      badgeClass: 'status-significant',
      overall: 58,
      cognitive: 68,
      speech: 63,
      motor: 65,
      interaction: 61,
      explanation: 'The combined pattern shows broader shifts across cognitive recall, speech fluency, motor steadiness, and interaction consistency.',
      contribution: { cognitive: 40, speech: 20, motor: 20, interaction: 20 },
      deviations: { cognitive: -24, speech: -19, motor: -15, interaction: -12 },
      recommendation: 'Consider professional consultation if these changes persist across repeated assessments.'
    };
  }
  return {
    status: 'LOW BEHAVIORAL DEVIATION',
    subtitle: 'Your current assessment remains largely consistent with your behavioral baseline.',
    badgeClass: 'status-stable',
    overall: 87,
    cognitive: 90,
    speech: 84,
    motor: 89,
    interaction: 82,
    explanation: 'Your memory and motor performance remained close to your established baseline. Slight variations were observed in speech timing and interaction consistency, but the combined pattern does not currently show substantial deviation.',
    contribution: { cognitive: 35, speech: 25, motor: 25, interaction: 15 },
    deviations: { cognitive: 2, speech: -3, motor: 1, interaction: -2 },
    recommendation: 'Continue routine monitoring and review changes over time.'
  };
}

function startAssessment() {
  state.completedAssessments = [];
  state.assessmentProgress = 0;
  state.reactionResults = [];
  state.reactionRound = 0;
  state.memoryInput = '';
  state.memoryVisible = true;
  state.memoryCountdown = 10;
  state.memoryStarted = false;
  state.speechRecorded = false;
  state.motorPath = [];
  state.motorMetrics = null;
  state.result = null;
  startMemoryAssessment();
  setScreen('memory');
}

function startMemoryAssessment() {
  state.memoryStarted = true;
  state.memoryVisible = true;
  state.memoryCountdown = 10;
  state.memoryInput = '';
  if (state.memoryTimerId) {
    clearInterval(state.memoryTimerId);
  }
  if (state.screen === 'memory') {
    render();
  }
  state.memoryTimerId = setInterval(() => {
    state.memoryCountdown -= 1;
    const countdownEl = document.getElementById('memoryCountdown');
    if (countdownEl) {
      countdownEl.textContent = state.memoryCountdown > 0 ? `${state.memoryCountdown} seconds` : 'Words hidden';
    }
    const promptEl = document.getElementById('memoryPrompt');
    if (promptEl) {
      promptEl.textContent = state.memoryCountdown > 0 ? 'The words will be hidden after the countdown.' : 'Enter as many words as you remember.';
    }
    const wordsEl = document.getElementById('memoryWords');
    if (wordsEl && state.memoryCountdown <= 0) {
      wordsEl.classList.add('hidden');
    }
    if (state.memoryCountdown <= 0) {
      clearInterval(state.memoryTimerId);
      state.memoryTimerId = null;
      state.memoryVisible = false;
    }
  }, 1000);
}

function completeAssessment(name) {
  if (!state.completedAssessments.includes(name)) {
    state.completedAssessments.push(name);
  }
  state.assessmentProgress = state.completedAssessments.length;
  render();
}

function submitMemory() {
  const targetWords = ['river', 'apple', 'chair', 'cloud', 'train'];
  const inputWords = state.memoryInput.toLowerCase().split(/\s+/).filter(Boolean);
  const recalled = inputWords.filter((word) => targetWords.includes(word));
  const accuracy = Math.round((recalled.length / targetWords.length) * 100);
  const consistency = accuracy >= 80 ? 'High' : accuracy >= 60 ? 'Moderate' : 'Low';
  const metric = { accuracy, recalledCount: recalled.length, consistency };
  state.result = { ...state.result, memory: metric };
  completeAssessment('memory');
  setScreen('reaction');
}

function startReactionTest() {
  state.reactionResults = [];
  state.reactionRound = 0;
  state.reactionReady = false;
  state.reactionStartedAt = 0;
  state.reactionInitialized = true;
  render();
  setTimeout(() => {
    state.reactionReady = true;
    state.reactionStartedAt = performance.now();
    render();
  }, 700 + Math.random() * 1000);
}

function handleReactionTap() {
  if (!state.reactionReady) return;
  const now = performance.now();
  const roundTime = Math.max(120, Math.round(now - state.reactionStartedAt));
  state.reactionResults.push({ timestamp: now, roundTime });
  state.reactionRound = state.reactionResults.length;
  state.reactionReady = false;
  if (state.reactionRound >= 5) {
    const avg = Math.round(state.reactionResults.reduce((sum, item) => sum + item.roundTime, 0) / state.reactionResults.length);
    const variability = avg > 320 ? 'Moderate' : 'Good';
    state.result = { ...state.result, reaction: { average: avg, variability } };
    completeAssessment('reaction');
    setTimeout(() => setScreen('speech'), 400);
    render();
    return;
  }
  setTimeout(() => {
    state.reactionReady = true;
    state.reactionStartedAt = performance.now();
    render();
  }, 600 + Math.random() * 800);
  render();
}

function startSpeechAssessment() {
  if (!navigator.mediaDevices?.getUserMedia) {
    state.result = { ...state.result, speech: { speechRate: 132, pauseFrequency: '8%', hesitationIndex: 'Low', consistency: '91%' } };
    completeAssessment('speech');
    setScreen('motor');
    return;
  }
  navigator.mediaDevices.getUserMedia({ audio: true }).then(() => {
    state.speechRecorded = true;
    state.result = { ...state.result, speech: { speechRate: 132, pauseFrequency: '8%', hesitationIndex: 'Low', consistency: '91%' } };
    completeAssessment('speech');
    setTimeout(() => setScreen('motor'), 700);
  }).catch(() => {
    state.result = { ...state.result, speech: { speechRate: 132, pauseFrequency: '8%', hesitationIndex: 'Low', consistency: '91%' } };
    completeAssessment('speech');
    setScreen('motor');
  });
}

function startMotorTest() {
  state.motorPath = [];
  state.motorMetrics = null;
  render();
}

function finishMotor() {
  const deviation = 6 + Math.random() * 5;
  const duration = 12 + Math.random() * 3;
  const smoothness = 88 + Math.random() * 5;
  const directionChanges = 18 + Math.random() * 7;
  state.motorMetrics = { deviation: deviation.toFixed(1), duration: duration.toFixed(1), smoothness: Math.round(smoothness), directionChanges: Math.round(directionChanges) };
  state.result = { ...state.result, motor: { stability: 89, consistency: 'Good' } };
  completeAssessment('motor');
  setTimeout(() => setScreen('analysis'), 400);
}

function beginAnalysis() {
  state.analysisStep = 0;
  const steps = [
    'Cognitive features extracted',
    'Speech features extracted',
    'Motor features extracted',
    'Interaction patterns evaluated',
    'Personal baseline comparison',
    'Risk indicators generated'
  ];
  let index = 0;
  const interval = setInterval(() => {
    state.analysisStep = index;
    if (index >= steps.length - 1) {
      clearInterval(interval);
      setTimeout(() => {
        state.result = state.result || getScenarioResult();
        setScreen('results');
      }, 700);
      return;
    }
    index += 1;
    render();
  }, 700);
  render();
}

function openReport() {
  setScreen('report');
}

function saveSession() {
  const scenario = getScenarioResult();
  const session = {
    timestamp: new Date().toISOString(),
    memoryScore: scenario.cognitive,
    reactionTime: 280 - (state.demoScenario === 'change' ? 18 : state.demoScenario === 'significant' ? 32 : 0),
    speechScore: scenario.speech,
    motorScore: scenario.motor,
    interactionScore: scenario.interaction,
    overallStability: scenario.overall,
    baselineDeviation: Math.max(1, 100 - scenario.overall) / 10
  };
  state.data.assessmentSessions.unshift(session);
  state.data.cognitiveMetrics.current = scenario.cognitive;
  state.data.speechMetrics.current = scenario.speech;
  state.data.motorMetrics.current = scenario.motor;
  state.data.interactionMetrics.current = scenario.interaction;
  saveData();
}

function handleResults() {
  saveSession();
  render();
}

function exportReport() {
  const report = `NeuroScan Behavioral Screening Report\nAssessment Date: ${new Date().toLocaleDateString()}\nOverall Status: ${state.result?.status || 'LOW BEHAVIORAL DEVIATION'}\nBehavioral Stability Score: ${state.result?.overall || 87}/100\nBaseline Comparison: ${state.demoScenario === 'stable' ? 'Within baseline' : 'Observed deviation'}\n\nSuggested next step: ${state.result?.recommendation || 'Continue routine monitoring.'}`;
  const blob = new Blob([report], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = 'neurascan-report.txt';
  link.click();
  URL.revokeObjectURL(url);
}

function render() {
  if (state.screen === 'splash') {
    app.innerHTML = `
      <section class="screen hero">
        <div class="hero-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24"><path d="M12 2c2.4 2.3 4.6 4.6 4.6 7.6 0 2.4-1.6 4.6-3.8 5.8 1 1.4 2 2.8 2.5 4.5-.9-.3-1.8-.7-2.7-1.2-1.2.6-2.6.9-4.1.9-1.7 0-3.3-.4-4.5-1.1.5-1.6 1.5-3.1 2.6-4.5-2.2-1.2-3.8-3.4-3.8-5.8C7.4 6.6 9.6 4.3 12 2Z"></path></svg>
        </div>
        <p class="eyebrow">NeuroScan AI</p>
        <h1>Intelligent Behavioral Screening for<br />Neurological Risk Analysis</h1>
        <p class="subhead">Understand changes in your cognitive, speech and motor patterns through smartphone-based behavioral screening.</p>
        <div class="cta-row">
          <button class="btn btn-primary" onclick="setScreen('onboarding')">Begin Screening</button>
          <button class="btn btn-secondary" onclick="setScreen('home')">How NeuroScan Works</button>
        </div>
        <p class="disclaimer">Research prototype — not a diagnostic medical device.</p>
      </section>
    `;
    return;
  }

  if (state.screen === 'onboarding') {
    const steps = [
      { title: 'Your Behavioral Fingerprint', description: 'NeuroScan establishes a personal baseline from cognitive, speech, motor and interaction patterns.' },
      { title: 'Track Changes Over Time', description: 'Future assessments can be compared against your own previous performance rather than relying only on population averages.' },
      { title: 'Understand the Signals', description: 'NeuroScan provides an explainable breakdown showing which behavioral domains contributed to the screening result.' }
    ];
    const step = steps[state.onboardingStep];
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Onboarding</p>
            <h2 class="title">NeuroScan AI</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="onboarding-step">
          <div class="icon">🧠</div>
          <h3 class="title">${step.title}</h3>
          <p class="small">${step.description}</p>
          <div class="dot-row">
            ${steps.map((_, index) => `<span class="dot ${index === state.onboardingStep ? 'active' : ''}"></span>`).join('')}
          </div>
          <div class="cta-row mt-12">
            <button class="btn btn-primary" onclick="${state.onboardingStep < steps.length - 1 ? 'state.onboardingStep += 1; render();' : "setScreen('home')"}">${state.onboardingStep < steps.length - 1 ? 'Continue' : 'Open Dashboard'}</button>
          </div>
        </div>
      </section>
    `;
    return;
  }

  if (state.screen === 'home') {
    const scenario = getScenarioResult();
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Good morning</p>
            <h2 class="title">NeuroScan AI</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <div class="eyebrow">Neurological Wellness Snapshot</div>
          <h3 class="title">Current Screening Status</h3>
          <div class="status-pill ${scenario.badgeClass}">${scenario.status}</div>
          <p class="small mt-8">${scenario.subtitle}</p>
          <div class="grid grid-2 mt-12">
            <div class="domain-card"><div class="label">Cognitive</div><div class="value">${scenario.cognitive} / 100</div><div class="sub">Stable</div></div>
            <div class="domain-card"><div class="label">Speech</div><div class="value">${scenario.speech} / 100</div><div class="sub">${scenario.speech < 80 ? 'Needs review' : 'Stable'}</div></div>
            <div class="domain-card"><div class="label">Motor</div><div class="value">${scenario.motor} / 100</div><div class="sub">Stable</div></div>
            <div class="domain-card"><div class="label">Interaction</div><div class="value">${scenario.interaction} / 100</div><div class="sub">${state.demoScenario === 'stable' ? 'Minor variation' : 'Shift observed'}</div></div>
          </div>
          <p class="small mt-12">Last screening: 3 days ago</p>
        </div>
        <button class="btn btn-primary mt-12" onclick="startAssessment()">Start Quick Scan</button>
        <div class="card mt-12">
          <div class="title">Baseline Progress</div>
          <p class="small">12 sessions recorded</p>
          <p class="small">Baseline confidence: 82%</p>
          <div class="progress-track">
            <div class="progress-fill" style="width: 82%"></div>
          </div>
        </div>
        <div class="card mt-12">
          <div class="title">Recent Activity</div>
          <div class="list mt-8">
            <div class="list-item"><div><strong>Memory Assessment</strong><div class="meta">3 days ago</div></div><div class="small">Normal variation</div></div>
            <div class="list-item"><div><strong>Speech Assessment</strong><div class="meta">5 days ago</div></div><div class="small">Stable</div></div>
            <div class="list-item"><div><strong>Motor Assessment</strong><div class="meta">7 days ago</div></div><div class="small">Stable</div></div>
          </div>
        </div>
        ${renderNav('home')}
      </section>
    `;
    return;
  }

  if (state.screen === 'quickScan') {
    const assessments = [
      { name: 'Memory Recall', desc: 'Tests short-term recall', time: '~45 sec', done: state.completedAssessments.includes('memory') },
      { name: 'Reaction Time', desc: 'Measures response consistency', time: '~30 sec', done: state.completedAssessments.includes('reaction') },
      { name: 'Speech Analysis', desc: 'Analyzes speech characteristics', time: '~45 sec', done: state.completedAssessments.includes('speech') },
      { name: 'Motor Control', desc: 'Measures tracing stability', time: '~30 sec', done: state.completedAssessments.includes('motor') }
    ];
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Assessment</p>
            <h2 class="title">Quick NeuroScan</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <p class="small">Complete four short behavioral assessments.</p>
        <div class="card">
          <div class="title">Progress</div>
          <p class="small">${state.assessmentProgress} / 4 assessments completed</p>
          <div class="progress-track"><div class="progress-fill" style="width:${(state.assessmentProgress / 4) * 100}%"></div></div>
        </div>
        <div class="mt-12">
          ${assessments.map((item) => `<div class="assessment-card ${item.done ? 'done' : ''} mt-8"><div><strong>${item.name}</strong><div class="meta">${item.desc}</div><div class="meta">${item.time}</div></div><div class="small">${item.done ? 'Complete' : 'Pending'}</div></div>`).join('')}
        </div>
        <button class="btn btn-primary mt-12" onclick="startAssessment()">Start Assessment</button>
        ${renderNav('assess')}
      </section>
    `;
    return;
  }

  if (state.screen === 'memory') {
    if (!state.memoryStarted) {
      startMemoryAssessment();
      return;
    }
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Assessment 1</p>
            <h2 class="title">Memory Recall</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <p class="small">Memorize the following words. They will disappear shortly.</p>
          <div class="words ${state.memoryVisible ? '' : 'hidden'}" id="memoryWords">
            ${['RIVER','APPLE','CHAIR','CLOUD','TRAIN'].map((w) => `<span class="word-chip">${w}</span>`).join('')}
          </div>
          <div class="metric" id="memoryCountdown">${state.memoryCountdown} seconds</div>
          <p class="small mt-8" id="memoryPrompt">${state.memoryVisible ? 'The words will be hidden after the countdown.' : 'Enter as many words as you remember.'}</p>
          <div class="input-row mt-12">
            <input id="memoryInput" placeholder="Type words you remember" value="${state.memoryInput}" onkeydown="if (event.key === 'Enter') { submitMemory(); }" oninput="state.memoryInput = this.value;" />
            <button class="btn btn-primary" onclick="submitMemory()">Submit</button>
          </div>
          <p class="small mt-8">Recall accuracy, response time and consistency will be calculated after submission.</p>
        </div>
      </section>
    `;
    return;
  }

  if (state.screen === 'reaction') {
    if (!state.reactionInitialized) {
      state.reactionInitialized = true;
      startReactionTest();
      return;
    }
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Assessment 2</p>
            <h2 class="title">Reaction Response</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <p class="small">Tap the screen as soon as the circle changes.</p>
          <div class="reaction-circle ${state.reactionReady ? 'ready' : 'waiting'}" onclick="handleReactionTap()">${state.reactionRound >= 5 ? 'Done' : state.reactionReady ? 'Tap Now' : state.reactionRound + '/5'}</div>
          <p class="small">${state.reactionRound >= 5 ? 'The assessment is complete.' : state.reactionReady ? 'The circle is now ready—tap as quickly as you can.' : 'A randomized delay will be introduced before the circle turns ready.'}</p>
        </div>
      </section>
    `;
    return;
  }

  if (state.screen === 'speech') {
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Assessment 3</p>
            <h2 class="title">Speech Pattern Assessment</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <p class="small">Speak naturally for 15 seconds about what you did yesterday.</p>
          <button class="btn btn-primary mt-12" onclick="startSpeechAssessment()">Start Recording</button>
          <div class="waveform mt-12">
            ${Array.from({ length: 16 }).map(() => '<span></span>').join('')}
          </div>
          <p class="small">00:00 / 00:15</p>
          <p class="small mt-8">Prototype behavioral metrics will be shown after recording.</p>
        </div>
      </section>
    `;
    return;
  }

  if (state.screen === 'motor') {
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Assessment 4</p>
            <h2 class="title">Motor Stability Test</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <p class="small">Trace the spiral slowly and stay as close to the guide as possible.</p>
          <svg class="spiral-canvas" id="motorCanvas" viewBox="0 0 320 260" onpointerdown="event.preventDefault(); state.motorPath = []; this.setPointerCapture(event.pointerId);" onpointermove="if (state.motorPath) { const rect = this.getBoundingClientRect(); const x = event.clientX - rect.left; const y = event.clientY - rect.top; state.motorPath.push({x,y}); renderMotorPath(); }" onpointerup="finishMotor()"></svg>
          <div class="mt-12">
            ${state.motorMetrics ? `<div class="title">Motor Stability ${state.motorMetrics.smoothness} / 100</div><p class="small">Movement consistency: Good</p><p class="small">Path deviation: ${state.motorMetrics.deviation}</p>` : '<p class="small">Your drawing will be evaluated after you finish tracing.</p>'}
          </div>
        </div>
      </section>
    `;
    setTimeout(() => renderMotorGuide(), 0);
    return;
  }

  if (state.screen === 'analysis') {
    const stages = ['Cognitive features extracted', 'Speech features extracted', 'Motor features extracted', 'Interaction patterns evaluated', 'Personal baseline comparison', 'Risk indicators generated'];
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Analysis</p>
            <h2 class="title">Analyzing Behavioral Signals</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <div class="analysis-list">
            ${stages.map((stage, index) => `<div class="item"><span>${stage}</span><span class="state">${index <= state.analysisStep ? 'Complete' : 'Pending'}</span></div>`).join('')}
          </div>
        </div>
      </section>
    `;
    if (state.analysisStep === 0) {
      beginAnalysis();
    }
    return;
  }

  if (state.screen === 'results') {
    const result = state.result || getScenarioResult();
    const overallScore = result.overall;
    const cognitive = result.cognitive;
    const speech = result.speech;
    const motor = result.motor;
    const interaction = result.interaction;
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Behavioral Report</p>
            <h2 class="title">NeuroScan Behavioral Report</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <div class="status-pill ${result.badgeClass}">${result.status}</div>
          <p class="small mt-8">${result.subtitle}</p>
          <p class="small mt-8">NeuroScan AI is a research screening prototype and does not provide a medical diagnosis. Screening results should not replace evaluation by a qualified healthcare professional.</p>
          <h3 class="metric mt-12">${overallScore} / 100</h3>
          <p class="small">Behavioral Stability Score</p>
          <div class="radar-card mt-12">
            ${renderRadarChart([cognitive, speech, motor, interaction])}
          </div>
        </div>
        <div class="card mt-12">
          <div class="title">Factor Breakdown</div>
          <div class="list mt-8">
            <div class="list-item"><div><strong>Cognitive Performance</strong><div class="meta">${cognitive >= 85 ? 'Within baseline' : 'Minor variation'}</div></div><div class="small">${cognitive} / 100</div></div>
            <div class="list-item"><div><strong>Speech Patterns</strong><div class="meta">${speech >= 80 ? 'Minor variation' : 'Needs review'}</div></div><div class="small">${speech} / 100</div></div>
            <div class="list-item"><div><strong>Motor Stability</strong><div class="meta">${motor >= 85 ? 'Within baseline' : 'Shift observed'}</div></div><div class="small">${motor} / 100</div></div>
            <div class="list-item"><div><strong>Interaction Patterns</strong><div class="meta">${interaction >= 80 ? 'Minor variation' : 'Shift observed'}</div></div><div class="small">${interaction} / 100</div></div>
          </div>
        </div>
        <div class="card mt-12">
          <div class="title">Why did I receive this result?</div>
          <p class="small mt-8">NeuroScan combines multiple behavioral signals rather than relying on a single assessment.</p>
          <div class="grid grid-2 mt-12">
            <div class="domain-card"><div class="label">Cognitive</div><div class="value">${result.contribution.cognitive}%</div></div>
            <div class="domain-card"><div class="label">Speech</div><div class="value">${result.contribution.speech}%</div></div>
            <div class="domain-card"><div class="label">Motor</div><div class="value">${result.contribution.motor}%</div></div>
            <div class="domain-card"><div class="label">Interaction</div><div class="value">${result.contribution.interaction}%</div></div>
          </div>
          <p class="small mt-12">${result.explanation}</p>
        </div>
        <div class="card mt-12">
          <div class="title">Behavioral Trends</div>
          <p class="small">Personal baselines allow NeuroScan to identify changes relative to your own previous behavioral patterns.</p>
          <div class="tabs mt-8">
            ${['overall','cognitive','speech','motor','interaction'].map((tab) => `<button class="${tab === state.trendTab ? 'active' : ''}" onclick="state.trendTab='${tab}'; render();">${capitalize(tab)}</button>`).join('')}
          </div>
          ${renderTrendChart()}
          <p class="small mt-8">Baseline established from 12 assessments. Baseline confidence: 82%</p>
        </div>
        <div class="cta-row mt-12">
          <button class="btn btn-primary" onclick="openReport()">View Detailed Report</button>
          <button class="btn btn-secondary" onclick="setScreen('privacy')">Privacy & Consent</button>
        </div>
        ${renderNav('insights')}
      </section>
    `;
    if (!state.result) {
      state.result = result;
      handleResults();
    }
    return;
  }

  if (state.screen === 'trends') {
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Insights</p>
            <h2 class="title">Behavioral Trends</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <div class="title">Behavioral Stability</div>
          <p class="small">Previous screening sessions</p>
          <div class="tabs mt-8">
            ${['overall','cognitive','speech','motor','interaction'].map((tab) => `<button class="${tab === state.trendTab ? 'active' : ''}" onclick="state.trendTab='${tab}'; render();">${capitalize(tab)}</button>`).join('')}
          </div>
          ${renderTrendChart()}
          <p class="small mt-8">Personal baseline established from 12 assessments with 82% confidence.</p>
        </div>
        ${renderNav('insights')}
      </section>
    `;
    return;
  }

  if (state.screen === 'report') {
    const result = state.result || getScenarioResult();
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Report</p>
            <h2 class="title">NeuroScan Behavioral Screening Report</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <div class="title">Assessment Date</div>
          <p class="small">${new Date().toLocaleDateString()}</p>
          <div class="status-pill ${result.badgeClass}">${result.status}</div>
          <p class="small mt-8">Behavioral stability score: ${result.overall}/100</p>
          <p class="small mt-8">Baseline comparison: ${state.demoScenario === 'stable' ? 'Within baseline' : 'Observed changes from baseline'}</p>
        </div>
        <div class="card mt-12">
          <div class="title">Screening interpretation</div>
          <p class="small mt-8">${result.explanation}</p>
          <p class="small mt-8">NeuroScan AI is a research screening prototype and does not provide a medical diagnosis. Screening results should not replace evaluation by a qualified healthcare professional.</p>
          <div class="title mt-12">Suggested next step</div>
          <p class="small mt-8">${result.recommendation}</p>
        </div>
        <div class="card mt-12">
          <div class="title">Export Report</div>
          <p class="small mt-8">A mock report can be shared with a qualified healthcare professional for context.</p>
          <button class="btn btn-primary mt-12" onclick="exportReport()">Export Report</button>
        </div>
      </section>
    `;
    return;
  }

  if (state.screen === 'privacy') {
    app.innerHTML = `
      <section class="screen">
        <div class="topbar">
          <div>
            <p class="eyebrow">Profile</p>
            <h2 class="title">Your Behavioral Data</h2>
          </div>
          <button class="badge" onclick="cycleDemoScenario()">Demo: ${state.demoScenario}</button>
        </div>
        <div class="card">
          <p class="small">Microphone access is only used during the speech assessment, motion sensors are used only during active assessments, and behavioral data should be encrypted.</p>
          <div class="toggle-row mt-12">
            <div><strong>Microphone</strong><div class="small">Used only for speech assessment</div></div>
            <label class="switch"><input type="checkbox" checked onchange="state.privacy.microphone = this.checked; render();" /><span class="slider"></span></label>
          </div>
          <div class="toggle-row">
            <div><strong>Motion Sensors</strong><div class="small">Used during assessments</div></div>
            <label class="switch"><input type="checkbox" checked onchange="state.privacy.motion = this.checked; render();" /><span class="slider"></span></label>
          </div>
          <div class="toggle-row">
            <div><strong>Behavioral Analytics</strong><div class="small">Used to compare against your baseline</div></div>
            <label class="switch"><input type="checkbox" checked onchange="state.privacy.analytics = this.checked; render();" /><span class="slider"></span></label>
          </div>
          <p class="small mt-12">Users control their screening history and can delete their data from the settings panel.</p>
        </div>
        ${renderNav('profile')}
      </section>
    `;
    return;
  }

  setScreen('splash');
}

function renderNav(active) {
  return `
    <div class="nav">
      <button class="${active === 'home' ? 'active' : ''}" onclick="setNavigation('home')">Home</button>
      <button class="${active === 'assess' ? 'active' : ''}" onclick="setNavigation('assess')">Assess</button>
      <button class="${active === 'insights' ? 'active' : ''}" onclick="setNavigation('insights')">Insights</button>
      <button class="${active === 'profile' ? 'active' : ''}" onclick="setNavigation('profile')">Profile</button>
    </div>
  `;
}

function renderRadarChart(scores) {
  const labels = ['Cognitive', 'Speech', 'Motor', 'Interaction'];
  const size = 220;
  const center = size / 2;
  const radius = 82;
  const points = scores.map((score, index) => {
    const angle = (Math.PI / 2) + (index * (Math.PI * 2 / 4));
    const x = center + Math.cos(angle) * (radius * (score / 100));
    const y = center - Math.sin(angle) * (radius * (score / 100));
    return `${x},${y}`;
  }).join(' ');
  return `
    <svg viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
      <polygon points="${points}" fill="rgba(20,108,122,0.2)" stroke="#146c7a" stroke-width="2"></polygon>
      ${labels.map((_, index) => {
        const angle = (Math.PI / 2) + (index * (Math.PI * 2 / 4));
        const x = center + Math.cos(angle) * radius;
        const y = center - Math.sin(angle) * radius;
        return `<line x1="${center}" y1="${center}" x2="${x}" y2="${y}" stroke="rgba(15,35,66,0.18)" stroke-width="1"></line>`;
      }).join('')}
      ${labels.map((label, index) => {
        const angle = (Math.PI / 2) + (index * (Math.PI * 2 / 4));
        const x = center + Math.cos(angle) * (radius + 18);
        const y = center - Math.sin(angle) * (radius + 18);
        return `<text x="${x}" y="${y}" text-anchor="middle" fill="#0f2342" font-size="10">${label}</text>`;
      }).join('')}
    </svg>
  `;
}

function renderTrendChart() {
  const selected = state.trendTab;
  const values = selected === 'overall'
    ? [89, 91, 88, 90, 87]
    : selected === 'cognitive'
      ? [88, 90, 89, 88, 90]
      : selected === 'speech'
        ? [86, 88, 85, 87, 84]
        : selected === 'motor'
          ? [90, 89, 87, 88, 89]
          : [84, 85, 83, 84, 82];
  const width = 300;
  const height = 150;
  const max = 100;
  const min = 80;
  const points = values.map((value, index) => {
    const x = 20 + (index * (width - 40) / (values.length - 1));
    const y = height - 20 - ((value - min) / (max - min)) * (height - 40);
    return `${x},${y}`;
  }).join(' ');
  const polyline = `<polyline points="${points}" fill="none" stroke="#146c7a" stroke-width="3"></polyline>`;
  const circles = values.map((value, index) => {
    const x = 20 + (index * (width - 40) / (values.length - 1));
    const y = height - 20 - ((value - min) / (max - min)) * (height - 40);
    return `<circle cx="${x}" cy="${y}" r="4" fill="#21d3c3"></circle>`;
  }).join('');
  return `
    <svg viewBox="0 0 ${width} ${height}" class="mt-12" xmlns="http://www.w3.org/2000/svg">
      <line x1="20" y1="130" x2="280" y2="130" stroke="#dfeaf0"></line>
      <line x1="20" y1="20" x2="20" y2="130" stroke="#dfeaf0"></line>
      ${polyline}
      ${circles}
    </svg>
  `;
}

function renderMotorGuide() {
  const canvas = document.getElementById('motorCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const width = canvas.clientWidth || 320;
  const height = canvas.clientHeight || 260;
  canvas.width = width;
  canvas.height = height;
  ctx.clearRect(0,0,width,height);
  ctx.strokeStyle = '#dfeaf0';
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let i = 0; i < 120; i += 1) {
    const angle = (i / 120) * Math.PI * 2 * 3;
    const radius = 20 + (i / 120) * 90;
    const x = width/2 + Math.cos(angle) * radius;
    const y = height/2 + Math.sin(angle) * radius;
    if (i === 0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
  }
  ctx.stroke();
}

function renderMotorPath() {
  const canvas = document.getElementById('motorCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (state.motorPath.length < 2) return;
  const width = canvas.clientWidth || 320;
  const height = canvas.clientHeight || 260;
  ctx.strokeStyle = '#146c7a';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(state.motorPath[0].x, state.motorPath[0].y);
  state.motorPath.slice(1).forEach((point) => ctx.lineTo(point.x, point.y));
  ctx.stroke();
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

window.onload = () => {
  render();
  saveData();
};
