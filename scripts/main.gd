extends Node2D
## 메인 장면. 게임이 시작되면 처음 불리는 곳.

## 화면 제목 (테스트에서 확인한다)
@onready var title: Label = $Title


## 순수 로직은 이렇게 작은 함수로 나눠 tests/ 에서 검사한다.
static func clamp_score(score: int) -> int:
	return clampi(score, 0, 999_999)
