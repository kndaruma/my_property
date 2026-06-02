CREATE TABLE IF NOT EXISTS `my_properties` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `dimension` INT(11) NOT NULL,
    `parent_dimension` INT(11) NOT NULL,
    `max_slots` INT(11) DEFAULT 100,
    `doors` LONGTEXT DEFAULT '[]',
    `lifts` LONGTEXT DEFAULT '[]',
    `keys` LONGTEXT DEFAULT '{}',
    `time` LONGTEXT DEFAULT NULL,
    `owner` VARCHAR(50) DEFAULT NULL,
    `price` INT(11) DEFAULT -1,
    `donate_expire` BIGINT DEFAULT 0,
    `is_rentable` TINYINT(1) DEFAULT 0,
    `rent_price_per_day` INT(11) DEFAULT 0,
    `renter` VARCHAR(50) DEFAULT NULL,
    `rent_expire` BIGINT DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_dimension` (`dimension`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `my_property_furniture` (
    `id` INT(11) NOT NULL,
    `house_id` INT(11) NOT NULL,
    `name` VARCHAR(50) NOT NULL,
    `model` VARCHAR(50) NOT NULL,
    `price` INT(11) DEFAULT 0,
    `coords` LONGTEXT NOT NULL,
    `rot` LONGTEXT NOT NULL,
    `no_collision` TINYINT(1) DEFAULT 0,
    `is_frozen` TINYINT(1) DEFAULT 1,
    `dimension` INT(11) NOT NULL,
    PRIMARY KEY (`id`, `house_id`),
    KEY `idx_house_id` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
