from maxreps.backend.models.enums import WeightUnit

POUNDS_PER_KILOGRAM = 2.2046226218


def epley(weight: float, reps: int) -> float:
    '''Calculate estimated one-rep max'''

    if weight <= 0:
        raise ValueError("Weight must be greater than zero")

    if reps <= 0:
        raise ValueError("Reps must be greater than zero")

    if reps == 1:
        return round(weight, 2)

    return round(weight * (1 + reps / 30), 2)


def pounds_to_kg(pounds: float) -> float:
    return pounds / POUNDS_PER_KILOGRAM


def kg_to_pounds(kilograms: float) -> float:
    return kilograms * POUNDS_PER_KILOGRAM


def to_kilograms(weight: float, unit: WeightUnit) -> float:
    if unit == WeightUnit.KG:
        return weight

    return pounds_to_kg(weight)


def from_kilograms(weight: float,unit: WeightUnit) -> float:
    if unit == WeightUnit.KG:
        return weight

    return kg_to_pounds(weight)