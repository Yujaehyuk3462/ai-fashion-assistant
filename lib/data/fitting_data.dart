class SimulationResult {
  final int id;
  final String title;
  final int score;
  final String top;
  final String bottom;
  final String topImg;
  final String bottomImg;
  final String fitImg;

  const SimulationResult({
    required this.id,
    required this.title,
    required this.score,
    required this.top,
    required this.bottom,
    required this.topImg,
    required this.bottomImg,
    required this.fitImg,
  });
}

const simulationResults = [
  SimulationResult(
    id: 1,
    title: '캐주얼 데일리',
    score: 95,
    top: '화이트 셔츠',
    bottom: '슬림 청바지',
    topImg: 'https://images.unsplash.com/photo-1624222244232-5f1ae13bbd53?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    bottomImg: 'https://images.unsplash.com/photo-1714143136372-ddaf8b606da7?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    fitImg: 'https://images.unsplash.com/photo-1532332248682-206cc786359f?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=500&w=350&q=80',
  ),
  SimulationResult(
    id: 2,
    title: '시크 모던',
    score: 88,
    top: '블루 버튼업',
    bottom: '블랙 슬랙스',
    topImg: 'https://images.unsplash.com/photo-1620812112510-ea35f4cc7875?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    bottomImg: 'https://images.unsplash.com/photo-1718252540617-6ecda2b56b57?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    fitImg: 'https://images.unsplash.com/photo-1586231912972-d0970f9ce787?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=500&w=350&q=80',
  ),
  SimulationResult(
    id: 3,
    title: '스마트 캐주얼',
    score: 82,
    top: '스트라이프 셔츠',
    bottom: '데님 팬츠',
    topImg: 'https://images.unsplash.com/photo-1524275461690-a79bfeaf1f3a?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    bottomImg: 'https://images.unsplash.com/photo-1542272604-787c3835535d?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=300&w=220&q=80',
    fitImg: 'https://images.unsplash.com/photo-1541980161-32fe8af73880?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=500&w=350&q=80',
  ),
];