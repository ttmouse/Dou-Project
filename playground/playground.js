const projects = [
 ['dsh-drag',9,['AI','DSH']],['dsh-generative-ui',8,['AI','DSH']],
 ['dsh-model-picker',9,['AI','DSH'],'进行中'],['dsh-muse',301,['AI','DSH','蓝色']],
 ['dsh-recent',33,['AI','DSH']],['dsh-session-jump',1,['AI','DSH']],
 ['dsh-taskboard',41,['AI','DSH']],['echo',4,['AI']],['Engineer',2,[]],
 ['Evergreen-Note',112,['AI','绿色']],['dsh-companion',155,['AI','DSH']],
 ['dsh-dingtalk-channel',3,['AI','DSH']],['dsh-doc-review',22,['AI','DSH'],'进行中'],
 ['500MRR',3,[]],['A-Task',13,['AI']],['ACE-Step',266,['AI']]
];
const modes = {
 original:['原版参照','保留完整路径、精确时间与彩色标签，用来观察调整前后的差别。'],
 refined:['轻量卡片','名字优先，分类标签降低权重；状态独立呈现，保留舒适的留白。'],
 compact:['紧凑卡片','压缩纵向空间，减少辅助信息，让同一屏容纳更多项目。'],
 quiet:['弱边界网格','用细分隔线代替卡片底色，让整个项目集合成为一个连续的阅读平面。']
};
let mode='refined', comparison='original', selected='';
const $=id=>document.getElementById(id);
const icon=type=>`<svg class="icon" aria-hidden="true" viewBox="0 0 16 16">${type==='git'?'<circle cx="4" cy="3" r="1.5"/><circle cx="12" cy="3" r="1.5"/><circle cx="4" cy="13" r="1.5"/><path d="M4 4.5v7M12 4.5v1A3.5 3.5 0 0 1 8.5 9H4"/>':'<rect x="2" y="3" width="12" height="11" rx="2"/><path d="M5 1v4m6-4v4M2 7h12"/>'}</svg>`;
function visibleProjects(query){return projects.filter(p=>p[0].toLowerCase().includes(query.trim().toLowerCase()));}
function card(project,variant,index){
 const [name,git,tags,status]=project;
 const fullPath=`~/Projects/${name}`;
 const shownTags=variant==='original'&&status?[...tags,status]:tags;
 const time=variant==='original'?'2026-10-23 14:28:12':index<8?'今天':'3 天前';
 return `<button class="card" data-project="${name}" aria-pressed="${selected===name}" aria-label="选择 ${name}">
 <span class="topline"><span class="name" title="${name}">${name}</span>${status&&variant!=='original'?`<span class="status" title="${status}"><i class="dot"></i>${status}</span>`:''}</span>
 <span class="path" title="${fullPath}">${variant==='original'||$('paths').checked?fullPath:'Projects'}</span>
 <span class="meta"><span title="示例时间：2026-10-23 14:28:12">${icon('date')}${time}</span><span title="Git 指标：${git}（沿用截图数值）">${icon('git')}${git}</span></span>
 <span class="bottom"><span class="tags">${shownTags.map(t=>`<span class="tag ${t==='进行中'?'state':t==='绿色'?'green':t==='蓝色'?'blue':''}">${t}</span>`).join('')}</span><span class="open-mark" aria-hidden="true">↗</span></span></button>`;
}
function pane(variant,items,isComparison){
 const choices=Object.entries(modes).map(([key,[label]])=>`<option value="${key}" ${variant===key?'selected':''}>${label}</option>`).join('');
 return `<section class="pane ${variant}" aria-label="${modes[variant][0]}"><div class="pane-title"><span>${isComparison?'对照方案':'当前方案'} · ${modes[variant][0]}</span>${isComparison?`<select id="comparison-mode" aria-label="对照方案">${choices}</select>`:'<span>悬停 / 点击可预览</span>'}</div><div class="grid">${items.length?items.map((p,i)=>card(p,variant,i)).join(''):'<div class="empty">没有匹配的项目，试试其他名称。</div>'}</div></section>`;
}
function render(){
 const items=visibleProjects($('search').value);
 $('count').textContent=`${items.length} 个项目`;
 $('direction-name').textContent=modes[mode][0];
 $('direction-text').textContent=modes[mode][1];
 document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)));
 $('boards').classList.toggle('compare',$('compare').checked);
 $('boards').innerHTML=pane(mode,items,false)+($('compare').checked?pane(comparison,items,true):'');
 document.body.classList.toggle('path-on',$('paths').checked);
 const comparisonSelect=$('comparison-mode');
 if(comparisonSelect) comparisonSelect.addEventListener('change',e=>{comparison=e.target.value;render();});
 document.querySelectorAll('[data-project]').forEach(b=>b.addEventListener('click',()=>{
  selected=selected===b.dataset.project?'':b.dataset.project;
  $('selection').textContent=selected?`已选中 ${selected}`:'点击卡片预览选中状态';render();
 }));
}
document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>{mode=b.dataset.mode;render();}));
['search','compare','paths'].forEach(id=>$(id).addEventListener('input',render));
$('spacing').addEventListener('input',()=>{document.documentElement.style.setProperty('--space',`${$('spacing').value}px`);$('space-value').textContent=$('spacing').value;});
$('theme').addEventListener('click',()=>{
 const dark=document.documentElement.dataset.theme==='dark';
 document.documentElement.dataset.theme=dark?'light':'dark';
 $('theme').textContent=dark?'切换深色':'切换浅色';
});
render();
