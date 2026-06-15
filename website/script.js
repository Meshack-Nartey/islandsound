const island = document.getElementById('island');
let state = 'collapsed';

function setState(next) {
  state = next;
  island.classList.toggle('is-expanded', state === 'expanded');
  island.classList.toggle('is-fullscreen', state === 'fullscreen');
}

island.addEventListener('mouseenter', () => {
  if (state === 'collapsed') setState('expanded');
});

island.addEventListener('mouseleave', () => {
  if (state === 'expanded') setState('collapsed');
});

island.addEventListener('click', () => {
  if (state === 'expanded') setState('fullscreen');
});

island.querySelector('.layer-fullscreen .icon-btn').addEventListener('click', (e) => {
  e.stopPropagation();
  setState('collapsed');
});

setState('collapsed');
